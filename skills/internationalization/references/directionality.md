# Internationalization — Directionality

Right-to-left (RTL) support through the `dir` attribute, CSS logical properties, icon mirroring rules, and RTL tests.

---

## The `dir` Attribute

Set `dir` once on `<html>` from the active locale. Every layout rule then follows the document direction; components never compute direction themselves.

| Lane                    | Where                     | How                                                                             |
| ----------------------- | ------------------------- | ------------------------------------------------------------------------------- |
| Vite                    | `src/i18n/index.ts`       | `i18next.on('languageChanged', ...)` sets `document.documentElement.dir`        |
| Next.js                 | `app/[locale]/layout.tsx` | `<html lang={locale} dir={getDirection(locale)}>`                               |
| Mixed-direction content | The element               | `<bdi>` for user-generated names, `dir="auto"` on inputs that accept any script |

Read the current direction in a component only when JavaScript must know it (keyboard arrow handling, canvas drawing):

```ts
// packages/ui/src/useDirection.ts
import { useSyncExternalStore } from 'react';

export type Direction = 'ltr' | 'rtl';

function subscribe(onChange: () => void) {
  const observer = new MutationObserver(onChange);
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ['dir'] });
  return () => observer.disconnect();
}

export function useDirection(): Direction {
  return useSyncExternalStore(
    subscribe,
    () => (document.documentElement.dir === 'rtl' ? 'rtl' : 'ltr'),
    () => 'ltr',
  );
}
```

Radix primitives read direction from `DirectionProvider` (`@radix-ui/react-direction`); render `<DirectionProvider dir={direction}>` at the app root so menus and sliders mirror.

---

## Logical Properties

| Physical (never)                           | Logical (always)                                                              | Notes                                                            |
| ------------------------------------------ | ----------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `margin-left` / `margin-right`             | `margin-inline-start` / `margin-inline-end`                                   | `margin-inline: a b` sets both                                   |
| `padding-left` / `padding-right`           | `padding-inline-start` / `padding-inline-end`                                 |                                                                  |
| `left` / `right`                           | `inset-inline-start` / `inset-inline-end`                                     | `inset-inline: 0` stretches                                      |
| `top` / `bottom`                           | `inset-block-start` / `inset-block-end`                                       | Unchanged by RTL, use for consistency                            |
| `border-left` / `border-right`             | `border-inline-start` / `border-inline-end`                                   |                                                                  |
| `border-top-left-radius`                   | `border-start-start-radius`                                                   | Four corners: `start-start`, `start-end`, `end-start`, `end-end` |
| `text-align: left` / `right`               | `text-align: start` / `end`                                                   |                                                                  |
| `float: left` / `right`                    | `float: inline-start` / `inline-end`                                          |                                                                  |
| `width` / `height`                         | `inline-size` / `block-size`                                                  | Optional; matters only for vertical writing modes                |
| `translateX(8px)`                          | `translateX(8px)` under `[dir='ltr']`, `translateX(-8px)` under `[dir='rtl']` | Transforms are physical; branch on `dir`                         |
| `background-position: left`                | `background-position: inline-start`                                           | Limited support; prefer flex alignment                           |
| `flex-direction: row-reverse` to "fix" RTL | `flex-direction: row`                                                         | Flex and grid already follow `dir`                               |

Tailwind v4 utilities: `ms-4`, `me-4`, `ps-4`, `pe-4`, `start-0`, `end-0`, `text-start`, `border-s`, `rounded-s-lg`. Never use `ml-4`, `mr-4`, `left-0`, `right-0`, `text-left`.

Enforce with Stylelint: `stylelint-use-logical` with `severity: error`, or `eslint-plugin-tailwindcss` `no-contradicting-classname` plus a custom rule banning physical utilities.

---

## Mirroring

| Mirror in RTL                                               | Never mirror                                                    |
| ----------------------------------------------------------- | --------------------------------------------------------------- |
| Back and forward arrows, chevrons, breadcrumb separators    | Media controls (play, fast-forward), because timelines stay LTR |
| "Send", "reply", "undo" arrows that imply reading direction | Clocks, checkmarks, question marks, logos                       |
| Progress steppers and sliders                               | Images of physical objects and people                           |
| Indentation and list markers (automatic)                    | Numbers, phone numbers, code samples (`dir="ltr"` on `<code>`)  |

```css
/* Directional icon component adds .icon-directional */
[dir='rtl'] .icon-directional {
  transform: scaleX(-1);
}
```

```tsx
// packages/ui/src/Icon.tsx
import type { ComponentProps } from 'react';

type IconProps = ComponentProps<'svg'> & { directional?: boolean; label?: string };

export function Icon({ directional = false, label, className = '', ...rest }: IconProps) {
  const classes = [directional ? 'icon-directional' : '', className].filter(Boolean).join(' ');
  return (
    <svg
      aria-hidden={label ? undefined : true}
      aria-label={label}
      role={label ? 'img' : undefined}
      focusable="false"
      className={classes === '' ? undefined : classes}
      {...rest}
    />
  );
}
```

---

## Bidirectional Text

- Wrap user-generated text of unknown script in `<bdi>` so a Hebrew name inside an English sentence does not scramble punctuation.
- Set `dir="auto"` on free-text inputs and textareas.
- Force `dir="ltr"` on codes, URLs, phone numbers, and monetary amounts inside RTL text.
- Never insert Unicode control characters (`‎`, `‫`) in translation strings; use markup.

---

## Testing RTL

### Unit

```tsx
// packages/ui/src/Icon.test.tsx
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Icon } from './Icon';

describe('Icon', () => {
  it('marks directional icons for mirroring', () => {
    render(<Icon directional label="Next" />);
    expect(screen.getByRole('img', { name: 'Next' })).toHaveClass('icon-directional');
  });

  it('hides decorative icons from assistive technology', () => {
    const { container } = render(<Icon />);
    expect(container.querySelector('svg')).toHaveAttribute('aria-hidden', 'true');
  });
});
```

### End to end

```ts
// e2e/rtl.spec.ts
import { expect, test } from '@playwright/test';

test.describe('Arabic locale', () => {
  test('sets document direction and mirrors navigation', async ({ page }) => {
    await page.goto('/ar');
    await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
    await expect(page.locator('html')).toHaveAttribute('lang', 'ar');

    const nav = page.getByRole('navigation', { name: /main/i });
    const first = await nav.getByRole('link').first().boundingBox();
    const last = await nav.getByRole('link').last().boundingBox();
    expect(first?.x ?? 0).toBeGreaterThan(last?.x ?? 0);
  });

  test('has no horizontal overflow', async ({ page }) => {
    await page.goto('/ar');
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
    expect(overflow).toBe(false);
  });

  test('matches the RTL snapshot', async ({ page }) => {
    await page.goto('/ar');
    await expect(page).toHaveScreenshot('home-ar.png', { fullPage: true });
  });
});
```

Storybook: add a `direction` global with a toolbar toggle that sets `dir` on the preview `<html>` so every story is reviewed in both directions.

```ts
// .storybook/preview.ts (excerpt)
import type { Decorator, Preview } from '@storybook/react';

const withDirection: Decorator = (Story, context) => {
  document.documentElement.dir = context.globals['direction'] === 'rtl' ? 'rtl' : 'ltr';
  return Story();
};

const preview: Preview = {
  decorators: [withDirection],
  globalTypes: {
    direction: {
      description: 'Text direction',
      toolbar: { title: 'Direction', items: ['ltr', 'rtl'] },
    },
  },
  initialGlobals: { direction: 'ltr' },
};

export default preview;
```
