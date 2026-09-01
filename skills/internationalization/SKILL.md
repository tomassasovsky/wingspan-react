---
name: react-internationalization
description: Best practices for internationalization (i18n) and localization (l10n) in React using react-i18next for Vite apps and next-intl for Next.js App Router apps. Use when adding, modifying, or reviewing translations, ICU messages, plurals, locale setup, language switching, number and date formatting, typed translation keys, message extraction, or RTL layout support.
allowed-tools: Read Glob Grep
---

# Internationalization

Internationalization (i18n) and localization (l10n) best practices for React applications with two lanes: `react-i18next` + `i18next` for Vite SPAs and `next-intl` for Next.js App Router, sharing ICU message format, `Intl.*` formatting, typed keys, and RTL support.

---

## Core Standards

Apply these standards to ALL internationalization work:

- **Never hard-code user-facing strings** — every visible string, `aria-label`, `alt`, `title`, and `placeholder` goes through `t()`
- **Use ICU message format for plurals, select, and arguments** — `{count, plural, one {# item} other {# items}}`; never build sentences by string concatenation
- **Namespace keys by feature** — `cart.summary.title`, not `title`; one namespace file per feature in the Vite lane, one top-level object per feature in the Next lane
- **Format numbers, dates, and relative time with `Intl.*`** — `Intl.NumberFormat`, `Intl.DateTimeFormat`, `Intl.RelativeTimeFormat`, `Intl.ListFormat`; never `toFixed`, `toLocaleString()` without a locale, or hand-written month arrays
- **Put the locale in the URL for Next.js** — `app/[locale]/` segment with `next-intl` middleware; Vite apps persist the choice in `localStorage` and read the `lng` query param
- **Lazy-load locale bundles** — `i18next-resources-to-backend` with dynamic `import()` per namespace; `next-intl` loads one `messages/<locale>.json` per request
- **RTL is `dir` on `<html>` plus CSS logical properties** — `margin-inline-start`, `inset-inline-end`, `text-align: start`; never `left`/`right` for layout
- **Type every translation key** — module augmentation of `i18next` `CustomTypeOptions` or `next-intl` `AppConfig`; unknown keys are compile errors
- **Extract keys mechanically** — `i18next-parser` in CI for Vite; a key-parity script for Next; missing translations fail the build
- **Pass localized strings into shared UI as props** — `packages/ui` components never import an i18n runtime
- **Set `lang` and `dir` on `<html>` from the active locale** — screen readers switch voices and browsers pick fonts from these attributes
- **Test with real `en` messages** — assert on rendered English text, never on raw keys

---

## Lane Selection

| Signal                                 | Lane    | Runtime                                                                                                       |
| -------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------- |
| `vite.config.ts`, React Router         | Vite    | `i18next`, `react-i18next`, `i18next-icu`, `i18next-browser-languagedetector`, `i18next-resources-to-backend` |
| `next.config.ts` with `app/` directory | Next.js | `next-intl` (ICU built in)                                                                                    |

Detect the lane from the project before writing anything. Never mix runtimes in one app.

---

## Message Format

Both lanes consume the same ICU syntax. Vite lane files live in `locales/<locale>/<namespace>.json`; Next lane files live in `messages/<locale>.json` with one top-level object per feature.

```json
{
  "title": "Your cart",
  "itemCount": "{count, plural, =0 {Your cart is empty} one {# item} other {# items}}",
  "total": "Total: {total}",
  "updatedAt": "Updated {time}",
  "greeting": "{gender, select, female {Welcome back, Ms. {name}} male {Welcome back, Mr. {name}} other {Welcome back, {name}}}",
  "checkout": "Check out"
}
```

Rules: keys are `camelCase`; values contain complete sentences; formatted numbers and dates are passed in as already-formatted arguments so translators control word order only.

---

## Setup

Full configuration for both lanes, including typed resources, `middleware.ts`, and `app/[locale]/layout.tsx`, is in [references/setup.md](references/setup.md).

### Vite lane

```ts
// src/i18n/index.ts
import i18next from 'i18next';
import LanguageDetector from 'i18next-browser-languagedetector';
import ICU from 'i18next-icu';
import resourcesToBackend from 'i18next-resources-to-backend';
import { initReactI18next } from 'react-i18next';

export const supportedLngs = ['en', 'es', 'ar'] as const;
export type SupportedLanguage = (typeof supportedLngs)[number];
export const defaultNS = 'common';

void i18next
  .use(ICU)
  .use(LanguageDetector)
  .use(resourcesToBackend((language: string, namespace: string) => import(`../../locales/${language}/${namespace}.json`)))
  .use(initReactI18next)
  .init({
    supportedLngs,
    fallbackLng: 'en',
    defaultNS,
    ns: [defaultNS],
    interpolation: { escapeValue: false },
    detection: { order: ['querystring', 'localStorage', 'navigator'], caches: ['localStorage'] },
  });

export default i18next;
```

A `languageChanged` listener sets `document.documentElement.lang` and `dir` (`i18next.dir(language)`). Import `./i18n` once in `main.tsx` and wrap the tree in `<Suspense>`; `useTranslation` suspends until the namespace bundle loads.

### Next.js lane

```ts
// src/i18n/routing.ts
import { defineRouting } from 'next-intl/routing';

export const routing = defineRouting({ locales: ['en', 'es', 'ar'], defaultLocale: 'en' });
export type Locale = (typeof routing.locales)[number];
```

`src/i18n/request.ts` validates `requestLocale` with `hasLocale(routing.locales, ...)`, falls back to `routing.defaultLocale`, and returns `{ locale, messages, timeZone }` from a dynamic `import()`. `middleware.ts` (or `proxy.ts` on Next 16+) exports `createMiddleware(routing)`; `app/[locale]/layout.tsx` calls `setRequestLocale`, sets `lang` and `dir`, and wraps children in `NextIntlClientProvider`.

---

## Components

### Vite lane

```tsx
// src/features/cart/components/CartSummary.tsx
import { useTranslation } from 'react-i18next';
import { formatCurrency, formatRelativeTime } from '@/i18n/format';

type CartSummaryProps = { count: number; total: number; currency: string; updatedAt: Date };

export function CartSummary({ count, total, currency, updatedAt }: CartSummaryProps) {
  const { t, i18n } = useTranslation('cart');
  const locale = i18n.resolvedLanguage ?? 'en';

  return (
    <section aria-labelledby="cart-summary-heading">
      <h2 id="cart-summary-heading">{t('title')}</h2>
      <p>{t('itemCount', { count })}</p>
      <p>{t('total', { total: formatCurrency(total, locale, currency) })}</p>
      <p>{t('updatedAt', { time: formatRelativeTime(updatedAt, locale) })}</p>
      <button type="button" disabled={count === 0}>{t('checkout')}</button>
    </section>
  );
}
```

### Next.js lane

```tsx
// src/features/cart/components/CartSummary.tsx
import { useFormatter, useTranslations } from 'next-intl';

type CartSummaryProps = { count: number; total: number; currency: string; updatedAt: Date };

export function CartSummary({ count, total, currency, updatedAt }: CartSummaryProps) {
  const t = useTranslations('Cart');
  const format = useFormatter();

  return (
    <section aria-labelledby="cart-summary-heading">
      <h2 id="cart-summary-heading">{t('title')}</h2>
      <p>{t('itemCount', { count })}</p>
      <p>{t('total', { total: format.number(total, { style: 'currency', currency }) })}</p>
      <p>{t('updatedAt', { time: format.relativeTime(updatedAt) })}</p>
      <button type="button" disabled={count === 0}>{t('checkout')}</button>
    </section>
  );
}
```

`useTranslations` works in Server and Client Components. Use `getTranslations` from `next-intl/server` in `generateMetadata` and route handlers.

---

## Formatting with Intl

Formatters are expensive to construct; cache them per locale and options. The full `format.ts` with dates, relative time, lists, and tests is in [references/setup.md](references/setup.md).

```ts
// src/i18n/format.ts (excerpt)
const numberFormatters = new Map<string, Intl.NumberFormat>();

export function formatCurrency(value: number, locale: string, currency: string): string {
  const key = `${locale}:${currency}`;
  let formatter = numberFormatters.get(key);
  if (!formatter) {
    formatter = new Intl.NumberFormat(locale, { style: 'currency', currency });
    numberFormatters.set(key, formatter);
  }
  return formatter.format(value);
}
```

| Need                     | API                                                | Never                                                  |
| ------------------------ | -------------------------------------------------- | ------------------------------------------------------ |
| Currency, percent, units | `Intl.NumberFormat`                                | `toFixed`, manual thousands separators                 |
| Dates and times          | `Intl.DateTimeFormat` with `dateStyle`/`timeStyle` | `getMonth()` lookups, `date-fns/format` without locale |
| Relative time            | `Intl.RelativeTimeFormat`                          | "x minutes ago" string templates                       |
| Lists                    | `Intl.ListFormat`                                  | `array.join(', ')`                                     |
| Language names           | `Intl.DisplayNames`                                | Hard-coded name tables                                 |
| Plurals                  | ICU `plural` in the message                        | `count === 1 ? 'item' : 'items'`                       |

---

## Language Switcher

```tsx
// src/components/LanguageSwitcher.tsx (Vite lane)
import { useTranslation } from 'react-i18next';
import { supportedLngs } from '@/i18n';

export function LanguageSwitcher() {
  const { t, i18n } = useTranslation();

  return (
    <label>
      {t('languageSwitcher.label')}
      <select value={i18n.resolvedLanguage} onChange={(event) => void i18n.changeLanguage(event.target.value)}>
        {supportedLngs.map((language) => (
          <option key={language} value={language} lang={language}>
            {new Intl.DisplayNames(language, { type: 'language' }).of(language)}
          </option>
        ))}
      </select>
    </label>
  );
}
```

Each option carries `lang` and shows the language in its own name, so a user who cannot read the current language can still find theirs. The Next.js switcher (in [references/setup.md](references/setup.md)) calls `router.replace({ pathname, params }, { locale })` from `@/i18n/navigation`.

---

## RTL

```css
/* Before */
.sidebar { margin-left: var(--space-4); border-right: 1px solid var(--color-border); text-align: left; }

/* After */
.sidebar { margin-inline-start: var(--space-4); border-inline-end: 1px solid var(--color-border); text-align: start; }
```

Directional icons (back, next, chevrons) flip with `[dir='rtl'] .icon-directional { transform: scaleX(-1); }`; media controls, clocks, and logos never flip. Full logical property table, mirroring rules, and RTL tests are in [references/directionality.md](references/directionality.md).

---

## Extraction and CI

| Lane    | Tool                        | Command             | CI gate                                                              |
| ------- | --------------------------- | ------------------- | -------------------------------------------------------------------- |
| Vite    | `i18next-parser`            | `pnpm i18n:extract` | `failOnUpdate: true` fails when source and `locales/en` diverge      |
| Next.js | `scripts/check-messages.ts` | `pnpm i18n:check`   | Fails when any locale is missing a key present in `messages/en.json` |
| Both    | TypeScript                  | `pnpm typecheck`    | Unknown keys are type errors                                         |

Configs are in [references/setup.md](references/setup.md). Loading messages from a backend or CDN, caching, and fallback are in [references/backend.md](references/backend.md).

---

## Testing

Render with a test i18n instance loaded with real `en` resources, assert on text, and cover plural branches and RTL. Full helpers for both lanes are in [references/testing.md](references/testing.md).

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

  it('formats currency and relative time for the active locale', () => {
    renderWithProviders(<CartSummary count={2} total={1234.5} currency="USD" updatedAt={updatedAt} />, { now });
    expect(screen.getByText('Total: $1,234.50')).toBeInTheDocument();
    expect(screen.getByText('Updated 5 minutes ago')).toBeInTheDocument();
  });
});
```

---

## Common Patterns

- **Adding a string** — add the key to `locales/en/<namespace>.json` (Vite) or the feature object in `messages/en.json` (Next); use it through `t('key', args)`; run `pnpm i18n:extract` or `pnpm i18n:check`; translate in every other locale
- **Adding a locale** — copy the `en` files and translate; add the code to `supportedLngs` or `routing.locales`; add it to the RTL set in `src/i18n/direction.ts` if it reads right to left; run the RTL Playwright suite

---

## Anti-Patterns

| Anti-Pattern                               | Problem                                                          | Correct Approach                                         |
| ------------------------------------------ | ---------------------------------------------------------------- | -------------------------------------------------------- |
| `<button>Save</button>`                    | Untranslatable; missed by extraction                             | `<button>{t('save')}</button>`                           |
| `` `${count} items` ``                     | Wrong for `one`, zero, and languages with more plural categories | ICU `plural` in the message                              |
| `t('hello') + ' ' + name`                  | Word order differs by language                                   | `t('hello', { name })` with `{name}` in the message      |
| `date.toLocaleDateString()`                | Uses the runtime locale, not the user's                          | `Intl.DateTimeFormat(locale, options)`                   |
| `price.toFixed(2)`                         | Wrong separators and currency symbol                             | `Intl.NumberFormat(locale, { style: 'currency' })`       |
| `margin-left` for layout                   | Breaks in RTL                                                    | `margin-inline-start`                                    |
| `t('errors.' + code)`                      | Keys invisible to extraction and typing                          | Map codes to keys in a typed `Record`, then `t(key)`     |
| Importing every locale eagerly             | Bundle grows with each language                                  | `i18next-resources-to-backend` or per-request `import()` |
| `useTranslation` inside `packages/ui`      | UI package couples to app runtime                                | Accept strings as props                                  |
| Asserting `screen.getByText('cart.title')` | Passes when translations are broken                              | Render with real `en` messages and assert on text        |
| Locale only in `localStorage` for Next.js  | Not shareable, not crawlable, hydration mismatch                 | `[locale]` URL segment                                   |
| Custom `Locale` type as `string`           | Any typo compiles                                                | `(typeof routing.locales)[number]`                       |

---

## Additional Resources

- [Setup](references/setup.md) — complete Vite and Next.js configuration, typed resources via module augmentation, `format.ts` with tests, Next.js switcher, extraction configs
- [Directionality](references/directionality.md) — RTL patterns, logical property table, icon mirroring rules, RTL testing
- [Backend](references/backend.md) — loading translations from a backend or CDN, caching, fallback, server-side error message mapping
- [Testing](references/testing.md) — test i18n instance, `renderWithProviders`, `next-intl` test provider, asserting on text, plural and RTL coverage
- [react-i18next documentation](https://react.i18next.com/)
- [next-intl documentation](https://next-intl.dev/docs)
- [ICU MessageFormat](https://unicode-org.github.io/icu/userguide/format_parse/messages/)
