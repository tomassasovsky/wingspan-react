# Accessibility — Testing

Automated and manual verification: `vitest-axe` in component tests, `@axe-core/playwright` per route, keyboard tests with `@testing-library/user-event`, ESLint enforcement, and the manual screen reader checklist.

---

## ESLint Enforcement

```bash
pnpm add -D eslint-plugin-jsx-a11y
```

```ts
// eslint.config.ts
import jsxA11y from 'eslint-plugin-jsx-a11y';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  jsxA11y.flatConfigs.strict,
  {
    files: ['**/*.tsx'],
    rules: {
      'jsx-a11y/no-autofocus': ['error', { ignoreNonDOM: true }],
      'jsx-a11y/anchor-is-valid': 'error',
      'jsx-a11y/control-has-associated-label': 'error',
    },
  },
);
```

`strict` upgrades every rule to `error`. Do not downgrade rules per project; fix the markup.

---

## vitest-axe Setup

```bash
pnpm add -D vitest-axe axe-core @testing-library/react @testing-library/user-event @testing-library/jest-dom jsdom
```

```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    coverage: { provider: 'v8', thresholds: { lines: 100, functions: 100, branches: 100, statements: 100 } },
  },
});
```

```ts
// src/test/setup.ts
import '@testing-library/jest-dom/vitest';
import * as axeMatchers from 'vitest-axe/matchers';
import { expect } from 'vitest';

expect.extend(axeMatchers);
```

```ts
// src/test/vitest-axe.d.ts
import 'vitest';
import type { AxeMatchers } from 'vitest-axe/matchers';

declare module 'vitest' {
  interface Assertion extends AxeMatchers {}
  interface AsymmetricMatchersContaining extends AxeMatchers {}
}
```

jsdom does not compute layout. Disable `color-contrast` in unit tests and verify contrast in Playwright:

```ts
// src/test/axe.ts
import { axe as runAxe } from 'vitest-axe';

export function axe(container: Element) {
  return runAxe(container, {
    rules: { 'color-contrast': { enabled: false } },
  });
}
```

### Component Test

```tsx
// packages/ui/src/TextField.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { axe } from '../../src/test/axe';
import { TextField } from './TextField';

describe('TextField', () => {
  it('has no axe violations with hint and error', async () => {
    const { container } = render(<TextField label="Email" hint="Work address" error="Enter a valid email" />);
    expect(await axe(container)).toHaveNoViolations();
  });

  it('associates label, hint, and error with the input', () => {
    render(<TextField label="Email" hint="Work address" error="Enter a valid email" />);
    const input = screen.getByRole('textbox', { name: 'Email' });

    expect(input).toHaveAccessibleDescription('Work address Enter a valid email');
    expect(input).toBeInvalid();
    expect(screen.getByRole('alert')).toHaveTextContent('Enter a valid email');
  });

  it('omits aria-describedby when there is nothing to describe', () => {
    render(<TextField label="Email" />);
    expect(screen.getByRole('textbox', { name: 'Email' })).not.toHaveAttribute('aria-describedby');
  });

  it('accepts typed input', async () => {
    const user = userEvent.setup();
    render(<TextField label="Email" />);
    await user.type(screen.getByRole('textbox', { name: 'Email' }), 'a@b.co');
    expect(screen.getByRole('textbox', { name: 'Email' })).toHaveValue('a@b.co');
  });
});
```

---

## Keyboard Tests with user-event

Assert focus order, activation keys, escape behavior, and focus restoration.

```tsx
// packages/ui/src/ConfirmDialog.test.tsx
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { axe } from '../../src/test/axe';
import { ConfirmDialog } from './ConfirmDialog';

function renderDialog(onConfirm = vi.fn()) {
  render(
    <ConfirmDialog
      trigger={<button type="button">Delete</button>}
      title="Delete project?"
      description="This cannot be undone."
      confirmLabel="Delete"
      cancelLabel="Cancel"
      onConfirm={onConfirm}
    />,
  );
  return { onConfirm };
}

describe('ConfirmDialog', () => {
  it('opens from the keyboard, traps focus, and restores it on Escape', async () => {
    const user = userEvent.setup();
    renderDialog();
    const trigger = screen.getByRole('button', { name: 'Delete' });

    await user.tab();
    await user.keyboard('{Enter}');
    const dialog = screen.getByRole('dialog', { name: 'Delete project?' });
    expect(dialog).toHaveAccessibleDescription('This cannot be undone.');
    expect(dialog).toContainElement(document.activeElement as HTMLElement);

    await user.tab();
    await user.tab();
    await user.tab();
    expect(dialog).toContainElement(document.activeElement as HTMLElement);

    await user.keyboard('{Escape}');
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(trigger).toHaveFocus();
  });

  it('confirms and closes', async () => {
    const user = userEvent.setup();
    const { onConfirm } = renderDialog();

    await user.click(screen.getByRole('button', { name: 'Delete' }));
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Delete' }));

    expect(onConfirm).toHaveBeenCalledOnce();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('has no axe violations while open', async () => {
    const user = userEvent.setup();
    renderDialog();
    await user.click(screen.getByRole('button', { name: 'Delete' }));
    expect(await axe(document.body)).toHaveNoViolations();
  });
});
```

Useful assertions from `@testing-library/jest-dom`: `toHaveFocus`, `toHaveAccessibleName`, `toHaveAccessibleDescription`, `toBeInvalid`, `toHaveAttribute('aria-expanded', 'true')`.

---

## Playwright with axe-core

```bash
pnpm add -D @playwright/test @axe-core/playwright
```

```ts
// e2e/fixtures/axe.ts
import AxeBuilder from '@axe-core/playwright';
import { test as base, expect, type Page } from '@playwright/test';

type Level = 'A' | 'AA' | 'AAA';

const tagsByLevel: Record<Level, string[]> = {
  A: ['wcag2a', 'wcag21a', 'wcag22a'],
  AA: ['wcag2a', 'wcag21a', 'wcag22a', 'wcag2aa', 'wcag21aa', 'wcag22aa'],
  AAA: ['wcag2a', 'wcag21a', 'wcag22a', 'wcag2aa', 'wcag21aa', 'wcag22aa', 'wcag2aaa'],
};

export async function expectNoViolations(page: Page, level: Level = 'AA') {
  const results = await new AxeBuilder({ page }).withTags(tagsByLevel[level]).analyze();
  expect(results.violations, JSON.stringify(results.violations, null, 2)).toEqual([]);
}

export const test = base;
export { expect };
```

```ts
// e2e/orders.a11y.spec.ts
import { expect, expectNoViolations, test } from './fixtures/axe';

test.describe('Orders page', () => {
  test('meets WCAG 2.2 AA', async ({ page }) => {
    await page.goto('/orders');
    await expectNoViolations(page, 'AA');
  });

  test('moves focus to the heading after navigation', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('link', { name: 'Orders' }).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Orders' })).toBeFocused();
  });

  test('skip link reaches main content', async ({ page }) => {
    await page.goto('/orders');
    await page.keyboard.press('Tab');
    await expect(page.getByRole('link', { name: 'Skip to main content' })).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(page.getByRole('main')).toBeFocused();
  });

  test('respects reduced motion', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto('/orders');
    const duration = await page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue('--motion-duration-fast').trim(),
    );
    expect(duration).toBe('0ms');
  });

  test('renders without horizontal scroll at 320px', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 800 });
    await page.goto('/orders');
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
    expect(overflow).toBe(false);
  });
});
```

Run every axe spec in CI; a single violation fails the pipeline.

---

## Manual Screen Reader Checklist

Automated tools catch roughly a third of WCAG failures. Complete this pass before release on every new route or component.

| Platform | Screen reader        | Browser           |
| -------- | -------------------- | ----------------- |
| macOS    | VoiceOver (`Cmd+F5`) | Safari            |
| Windows  | NVDA (free)          | Chrome or Firefox |
| Windows  | JAWS                 | Chrome            |
| iOS      | VoiceOver            | Safari            |
| Android  | TalkBack             | Chrome            |

Checklist:

- [ ] Page title announced on load and after every route change
- [ ] Skip link is the first `Tab` stop and moves focus to `<main>`
- [ ] Landmark navigation (VoiceOver rotor, NVDA `D`) lists header, navigation, main, footer with distinct names
- [ ] Heading navigation (`H` key) reads a sensible outline; one `h1`; no skipped levels
- [ ] Every control announces name, role, and state; nothing is announced as "clickable" or "group" without a name
- [ ] Icon buttons announce their purpose, not "button"
- [ ] Form fields announce label, required state, hint, and error; errors announced on submit
- [ ] Opening a dialog announces its title; `Tab` stays inside; `Escape` returns focus to the trigger
- [ ] Menus, tabs, and comboboxes follow the arrow-key patterns in [element-mapping.md](element-mapping.md)
- [ ] Async status (saving, saved, failed) announced without moving focus
- [ ] Tables announce column and row headers while navigating cells
- [ ] Images announce meaningful `alt`; decorative images are skipped
- [ ] Zoom to 200% and 400%: no clipped text, no horizontal scroll, all controls still reachable
- [ ] `prefers-reduced-motion: reduce`: no non-essential animation plays
- [ ] Keyboard only, no screen reader: focus always visible; no traps; no dead ends
