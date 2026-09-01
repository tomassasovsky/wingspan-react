# Internationalization — Testing

Rendering components with a test i18n instance, `renderWithProviders`, the `next-intl` test provider, asserting on text rather than keys, and covering plurals, formatting, and RTL.

---

## Principles

| Rule                                   | Reason                                                                  |
| -------------------------------------- | ----------------------------------------------------------------------- |
| Load real `en` messages in tests       | Tests fail when a key is missing, renamed, or malformed ICU             |
| Assert on rendered text, never on keys | `getByText('cart.title')` passes while the UI shows raw keys            |
| Pin `now` and `timeZone`               | Relative time and dates are otherwise flaky across machines             |
| Cover every plural branch              | `=0`, `one`, `other` at minimum; `few`/`many` for locales that use them |
| Query by role and accessible name      | Names come from translations, so this also verifies `aria-label` wiring |
| Keep the test instance synchronous     | No lazy loading or detection in tests; resources are passed inline      |

---

## Vite Lane

### Test instance

```ts
// src/test/i18n.ts
import i18next from 'i18next';
import ICU from 'i18next-icu';
import { initReactI18next } from 'react-i18next';
import auth from '../../locales/en/auth.json';
import cart from '../../locales/en/cart.json';
import common from '../../locales/en/common.json';

export const testI18n = i18next.createInstance();

void testI18n
  .use(ICU)
  .use(initReactI18next)
  .init({
    lng: 'en',
    fallbackLng: 'en',
    defaultNS: 'common',
    ns: ['common', 'cart', 'auth'],
    resources: { en: { common, cart, auth } },
    interpolation: { escapeValue: false },
    react: { useSuspense: false },
  });
```

Add each new namespace here as it is created; the typed `CustomTypeOptions` from `src/i18n/i18next.d.ts` already cover it.

### `renderWithProviders`

```tsx
// src/test/render.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, type RenderOptions } from '@testing-library/react';
import type { ReactElement, ReactNode } from 'react';
import { I18nextProvider } from 'react-i18next';
import { MemoryRouter } from 'react-router';
import { vi } from 'vitest';
import { testI18n } from './i18n';

type Options = Omit<RenderOptions, 'wrapper'> & {
  route?: string;
  language?: 'en' | 'es' | 'ar';
  now?: Date;
};

export function renderWithProviders(ui: ReactElement, { route = '/', language = 'en', now, ...options }: Options = {}) {
  if (now) vi.setSystemTime(now);
  if (testI18n.language !== language) void testI18n.changeLanguage(language);
  document.documentElement.dir = testI18n.dir(language);

  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });

  function Wrapper({ children }: { children: ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        <I18nextProvider i18n={testI18n}>
          <MemoryRouter initialEntries={[route]}>{children}</MemoryRouter>
        </I18nextProvider>
      </QueryClientProvider>
    );
  }

  return render(ui, { wrapper: Wrapper, ...options });
}
```

```ts
// src/test/setup.ts (excerpt)
import '@testing-library/jest-dom/vitest';
import { afterEach, vi } from 'vitest';

afterEach(() => {
  vi.useRealTimers();
});
```

`vi.setSystemTime` mocks `Date` without faking timers, so `user-event` keeps working; `vi.useRealTimers()` restores the clock after each test.

### Component test

```tsx
// src/features/cart/components/CartSummary.test.tsx
import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { renderWithProviders } from '@/test/render';
import { CartSummary } from './CartSummary';

const updatedAt = new Date('2026-01-01T11:55:00Z');
const now = new Date('2026-01-01T12:00:00Z');

describe('CartSummary', () => {
  it.each([
    [0, 'Your cart is empty'],
    [1, '1 item'],
    [3, '3 items'],
  ])('renders the plural form for %i', (count, expected) => {
    renderWithProviders(<CartSummary count={count} total={10} currency="USD" updatedAt={updatedAt} />, { now });
    expect(screen.getByText(expected)).toBeInTheDocument();
  });

  it('formats currency and relative time', () => {
    renderWithProviders(<CartSummary count={2} total={1234.5} currency="USD" updatedAt={updatedAt} />, { now });
    expect(screen.getByText('Total: $1,234.50')).toBeInTheDocument();
    expect(screen.getByText('Updated 5 minutes ago')).toBeInTheDocument();
  });

  it('disables checkout when the cart is empty', () => {
    renderWithProviders(<CartSummary count={0} total={0} currency="USD" updatedAt={updatedAt} />, { now });
    expect(screen.getByRole('button', { name: 'Check out' })).toBeDisabled();
  });
});
```

### Language switcher test

```tsx
// src/components/LanguageSwitcher.test.tsx
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it } from 'vitest';
import { testI18n } from '@/test/i18n';
import { renderWithProviders } from '@/test/render';
import { LanguageSwitcher } from './LanguageSwitcher';

describe('LanguageSwitcher', () => {
  afterEach(async () => {
    await testI18n.changeLanguage('en');
  });

  it('lists every language in its own name', () => {
    renderWithProviders(<LanguageSwitcher />);
    expect(screen.getByRole('option', { name: 'English' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'español' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'العربية' })).toBeInTheDocument();
  });

  it('changes the active language', async () => {
    const user = userEvent.setup();
    renderWithProviders(<LanguageSwitcher />);
    await user.selectOptions(screen.getByRole('combobox', { name: 'Language' }), 'ar');
    expect(testI18n.language).toBe('ar');
  });
});
```

---

## Next.js Lane

### Test provider

```tsx
// src/test/render.tsx
import { render, type RenderOptions } from '@testing-library/react';
import { NextIntlClientProvider } from 'next-intl';
import type { ReactElement, ReactNode } from 'react';
import messages from '../../messages/en.json';

type Options = Omit<RenderOptions, 'wrapper'> & { locale?: 'en' | 'es' | 'ar'; now?: Date };

export function renderWithProviders(ui: ReactElement, { locale = 'en', now, ...options }: Options = {}) {
  function Wrapper({ children }: { children: ReactNode }) {
    return (
      <NextIntlClientProvider locale={locale} messages={messages} timeZone="UTC" now={now}>
        {children}
      </NextIntlClientProvider>
    );
  }
  return render(ui, { wrapper: Wrapper, ...options });
}
```

`NextIntlClientProvider` accepts `now`, which drives `format.relativeTime`, so no fake timers are needed. For locales other than `en`, import that locale's messages and pass them; keep `en` as the default so most tests read naturally.

### Component test

The `CartSummary` test from the Vite lane runs unchanged against this `renderWithProviders`.

### Server Components

`useTranslations` in a Server Component is synchronous and works under `renderWithProviders`. Async Server Components that call `getTranslations` are tested through Playwright, not `@testing-library/react`.

### Navigation mocks

```ts
// src/test/setup.ts (excerpt)
import { createElement, type ReactNode } from 'react';
import { vi } from 'vitest';

vi.mock('@/i18n/navigation', () => ({
  Link: ({ href, children }: { href: string; children: ReactNode }) => createElement('a', { href }, children),
  usePathname: () => '/',
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
}));
```

Mock only the navigation module; never mock `next-intl` itself, or the tests stop exercising real messages.

---

## Linting Tests for Hard-Coded Strings

```ts
// eslint.config.ts (excerpt)
import i18next from 'eslint-plugin-i18next';

export default [
  {
    files: ['src/**/*.tsx'],
    ignores: ['src/**/*.test.tsx', 'src/**/*.stories.tsx'],
    plugins: { i18next },
    rules: {
      'i18next/no-literal-string': ['error', { markupOnly: true, ignoreAttribute: ['data-testid', 'className', 'href', 'to', 'type', 'role'] }],
    },
  },
];
```

Tests and stories are excluded on purpose: they assert on literal English text.

---

## Playwright Locale Coverage

```ts
// e2e/locale.spec.ts
import { expect, test } from '@playwright/test';

for (const locale of ['en', 'es', 'ar'] as const) {
  test(`checkout renders in ${locale}`, async ({ page }) => {
    await page.goto(`/${locale}/checkout`);
    await expect(page.locator('html')).toHaveAttribute('lang', locale);
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    await expect(page.getByText(/\b[a-z]+\.[a-zA-Z]+\.[a-zA-Z]+\b/)).toHaveCount(0);
  });
}
```

The last assertion fails when any raw `namespace.key.path` leaks into the page, which is the most common regression when a message file is out of sync.
