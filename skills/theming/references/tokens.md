# Theming — Token Catalog

Naming convention, the three token layers, the full semantic catalog, the complete Tailwind CSS v4 `@theme` mapping, and breakpoints.

---

## Naming Convention

```text
--<layer-prefix>-<category>-<role>[-<modifier>][-<state>]
```

| Part         | Values                                                                                                       | Examples                                               |
| ------------ | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------ |
| Layer prefix | `palette` (primitive color), none (semantic), `<component>` (component)                                      | `--palette-blue-600`, `--color-primary`, `--button-bg` |
| Category     | `color`, `space`, `text`, `leading`, `font-family`, `font-weight`, `radius`, `shadow`, `motion`, `size`, `z` | `--space-4`, `--radius-md`, `--z-dialog`               |
| Role         | Intent, not appearance                                                                                       | `primary`, `surface`, `danger`, `on-surface`           |
| Modifier     | `muted`, `raised`, `subtle`, `strong`                                                                        | `--color-on-surface-muted`                             |
| State        | `hover`, `active`, `disabled`                                                                                | `--color-primary-hover`                                |

Rules: lowercase, hyphen-separated, no abbreviations except `bg`/`fg` in component tokens, numeric steps for scales (`--space-4`), t-shirt sizes for shape and type (`--radius-md`, `--text-body-md`).

---

## Primitive Layer

Primitives live in `primitives.css`, are never read by components, and change only when the brand changes.

```css
/* packages/ui/src/styles/primitives.css */
:root {
  --palette-neutral-0: oklch(100% 0 0);
  --palette-neutral-50: oklch(98% 0.003 260);
  --palette-neutral-100: oklch(96% 0.005 260);
  --palette-neutral-200: oklch(91% 0.008 260);
  --palette-neutral-300: oklch(85% 0.01 260);
  --palette-neutral-400: oklch(70% 0.015 260);
  --palette-neutral-500: oklch(60% 0.02 260);
  --palette-neutral-600: oklch(52% 0.02 260);
  --palette-neutral-700: oklch(40% 0.02 260);
  --palette-neutral-800: oklch(28% 0.02 260);
  --palette-neutral-900: oklch(20% 0.02 260);
  --palette-neutral-950: oklch(14% 0.02 260);

  --palette-blue-100: oklch(94% 0.04 260);
  --palette-blue-400: oklch(72% 0.16 260);
  --palette-blue-600: oklch(55% 0.2 260);
  --palette-blue-700: oklch(48% 0.2 260);
  --palette-blue-900: oklch(30% 0.12 260);

  --palette-green-600: oklch(58% 0.17 150);
  --palette-green-400: oklch(75% 0.17 150);
  --palette-amber-600: oklch(70% 0.17 75);
  --palette-amber-400: oklch(82% 0.15 75);
  --palette-red-600: oklch(55% 0.22 25);
  --palette-red-400: oklch(70% 0.19 25);

  --size-1: 0.25rem;
  --size-2: 0.5rem;
  --size-3: 0.75rem;
  --size-4: 1rem;
  --size-5: 1.25rem;
  --size-6: 1.5rem;
  --size-8: 2rem;
  --size-10: 2.5rem;
  --size-12: 3rem;
  --size-16: 4rem;
  --size-20: 5rem;
  --size-24: 6rem;
}
```

`oklch` keeps perceived lightness consistent across hues, so the same step number has the same contrast against a given surface in every hue.

---

## Semantic Layer

### Color

| Token                         | Light                 | Dark                  | Use                                                  |
| ----------------------------- | --------------------- | --------------------- | ---------------------------------------------------- |
| `--color-surface`             | `neutral-0`           | `neutral-950`         | Page background                                      |
| `--color-surface-raised`      | `neutral-100`         | `neutral-900`         | Cards, menus, dialogs                                |
| `--color-surface-sunken`      | `neutral-50`          | `neutral-950`         | Wells, code blocks                                   |
| `--color-on-surface`          | `neutral-900`         | `neutral-100`         | Body text, icons                                     |
| `--color-on-surface-muted`    | `neutral-600`         | `neutral-300`         | Secondary text (4.5:1 minimum)                       |
| `--color-on-surface-disabled` | `neutral-400`         | `neutral-600`         | Disabled text (exempt from contrast)                 |
| `--color-border`              | `neutral-300`         | `neutral-800`         | Dividers, input borders (3:1 minimum)                |
| `--color-border-strong`       | `neutral-500`         | `neutral-500`         | Emphasized borders                                   |
| `--color-primary`             | `blue-600`            | `blue-400`            | Primary actions, links                               |
| `--color-primary-hover`       | `blue-700`            | `blue-600`            | Hover state                                          |
| `--color-primary-subtle`      | `blue-100`            | `blue-900`            | Selected rows, badges                                |
| `--color-on-primary`          | `neutral-0`           | `neutral-950`         | Text on primary                                      |
| `--color-on-primary-subtle`   | `blue-900`            | `blue-100`            | Text on primary-subtle                               |
| `--color-success`             | `green-600`           | `green-400`           | Success state                                        |
| `--color-warning`             | `amber-600`           | `amber-400`           | Warning state                                        |
| `--color-danger`              | `red-600`             | `red-400`             | Errors, destructive actions                          |
| `--color-on-danger`           | `neutral-0`           | `neutral-950`         | Text on danger                                       |
| `--color-focus-ring`          | `blue-600`            | `blue-400`            | `:focus-visible` outline (3:1 against both surfaces) |
| `--color-overlay`             | `oklch(0% 0 0 / 0.5)` | `oklch(0% 0 0 / 0.7)` | Dialog backdrop                                      |

Every `on-*` pair is verified against its surface at 4.5:1 (text) or 3:1 (UI) in both themes before merge; the Playwright axe suite is the gate.

### Spacing, shape, elevation, layering

| Token           | Value                              | Use                                              |
| --------------- | ---------------------------------- | ------------------------------------------------ |
| `--space-0`     | `0`                                | Reset                                            |
| `--space-1`     | `0.25rem` (4px)                    | Icon gaps, tight inline                          |
| `--space-2`     | `0.5rem` (8px)                     | Inline gaps, chip padding                        |
| `--space-3`     | `0.75rem` (12px)                   | Input padding                                    |
| `--space-4`     | `1rem` (16px)                      | Default component padding                        |
| `--space-6`     | `1.5rem` (24px)                    | Card padding, section gaps                       |
| `--space-8`     | `2rem` (32px)                      | Between groups                                   |
| `--space-12`    | `3rem` (48px)                      | Section spacing                                  |
| `--space-16`    | `4rem` (64px)                      | Page sections                                    |
| `--radius-sm`   | `0.25rem`                          | Inputs, chips                                    |
| `--radius-md`   | `0.5rem`                           | Buttons, cards                                   |
| `--radius-lg`   | `1rem`                             | Dialogs, sheets                                  |
| `--radius-full` | `9999px`                           | Pills, avatars                                   |
| `--shadow-sm`   | `0 1px 2px oklch(0% 0 0 / 0.08)`   | Raised controls                                  |
| `--shadow-md`   | `0 4px 12px oklch(0% 0 0 / 0.12)`  | Cards, popovers                                  |
| `--shadow-lg`   | `0 12px 32px oklch(0% 0 0 / 0.18)` | Dialogs                                          |
| `--z-dropdown`  | `100`                              | Menus, selects                                   |
| `--z-sticky`    | `200`                              | Sticky headers                                   |
| `--z-overlay`   | `300`                              | Backdrops                                        |
| `--z-dialog`    | `400`                              | Dialogs, sheets                                  |
| `--z-toast`     | `500`                              | Toasts                                           |
| `--size-header` | `4rem`                             | Header height; also `scroll-padding-block-start` |
| `--size-target` | `44px`                             | Minimum interactive target                       |

### Motion

| Token                        | Default                      | Reduced motion | Use                               |
| ---------------------------- | ---------------------------- | -------------- | --------------------------------- |
| `--motion-duration-fast`     | `150ms`                      | `0ms`          | Hover, focus, toggles             |
| `--motion-duration-base`     | `250ms`                      | `0ms`          | Menus, popovers, disclosure       |
| `--motion-duration-slow`     | `400ms`                      | `0ms`          | Dialogs, sheets, page transitions |
| `--motion-easing-standard`   | `cubic-bezier(0.2, 0, 0, 1)` | unchanged      | Enter and move                    |
| `--motion-easing-exit`       | `cubic-bezier(0.4, 0, 1, 1)` | unchanged      | Exit                              |
| `--motion-easing-emphasized` | `cubic-bezier(0.3, 0, 0, 1)` | unchanged      | Large surfaces                    |

Typography tokens are cataloged in [typography.md](typography.md).

---

## Component Layer

Component tokens are declared on the component's root selector, alias semantic tokens, and are the only thing variants change.

```css
.card {
  --card-bg: var(--color-surface-raised);
  --card-border: var(--color-border);
  --card-padding: var(--space-6);
  --card-radius: var(--radius-md);
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  padding: var(--card-padding);
  border-radius: var(--card-radius);
}
.card--compact { --card-padding: var(--space-4); }
.card--selected { --card-border: var(--color-primary); --card-bg: var(--color-primary-subtle); }
```

Component tokens never leak: another component must not read `--card-bg`.

---

## Tailwind CSS v4 Mapping

`@theme` declares semantic tokens once; Tailwind emits them on `:root` and generates utilities that read them with `var()`. Colors use `light-dark()`, so `data-theme` only needs to set `color-scheme`.

```css
/* apps/web/src/app.css */
@import 'tailwindcss';
@import '@acme/ui/styles/primitives.css';

@theme {
  /* Remove the default palette; only semantic colors exist */
  --color-*: initial;

  --color-surface: light-dark(var(--palette-neutral-0), var(--palette-neutral-950));
  --color-surface-raised: light-dark(var(--palette-neutral-100), var(--palette-neutral-900));
  --color-surface-sunken: light-dark(var(--palette-neutral-50), var(--palette-neutral-950));
  --color-on-surface: light-dark(var(--palette-neutral-900), var(--palette-neutral-100));
  --color-on-surface-muted: light-dark(var(--palette-neutral-600), var(--palette-neutral-300));
  --color-on-surface-disabled: light-dark(var(--palette-neutral-400), var(--palette-neutral-600));
  --color-border: light-dark(var(--palette-neutral-300), var(--palette-neutral-800));
  --color-border-strong: var(--palette-neutral-500);
  --color-primary: light-dark(var(--palette-blue-600), var(--palette-blue-400));
  --color-primary-hover: light-dark(var(--palette-blue-700), var(--palette-blue-600));
  --color-primary-subtle: light-dark(var(--palette-blue-100), var(--palette-blue-900));
  --color-on-primary: light-dark(var(--palette-neutral-0), var(--palette-neutral-950));
  --color-on-primary-subtle: light-dark(var(--palette-blue-900), var(--palette-blue-100));
  --color-success: light-dark(var(--palette-green-600), var(--palette-green-400));
  --color-warning: light-dark(var(--palette-amber-600), var(--palette-amber-400));
  --color-danger: light-dark(var(--palette-red-600), var(--palette-red-400));
  --color-on-danger: light-dark(var(--palette-neutral-0), var(--palette-neutral-950));
  --color-focus-ring: light-dark(var(--palette-blue-600), var(--palette-blue-400));
  --color-overlay: light-dark(oklch(0% 0 0 / 0.5), oklch(0% 0 0 / 0.7));
  --color-shadow: light-dark(oklch(0% 0 0 / 0.12), oklch(0% 0 0 / 0.5));

  /* Spacing: p-1 = 4px, p-4 = 16px */
  --spacing: 0.25rem;

  --font-sans: 'Inter Variable', system-ui, sans-serif;
  --font-mono: 'JetBrains Mono', ui-monospace, monospace;

  --text-*: initial;
  --text-body-sm: 0.875rem;
  --text-body-sm--line-height: 1.25rem;
  --text-body-md: 1rem;
  --text-body-md--line-height: 1.5rem;
  --text-body-lg: 1.125rem;
  --text-body-lg--line-height: 1.75rem;
  --text-title-sm: 1.25rem;
  --text-title-sm--line-height: 1.75rem;
  --text-title-sm--font-weight: 600;
  --text-title-md: 1.5rem;
  --text-title-md--line-height: 2rem;
  --text-title-md--font-weight: 600;
  --text-title-lg: 2rem;
  --text-title-lg--line-height: 2.5rem;
  --text-title-lg--font-weight: 600;
  --text-display: clamp(2.5rem, 2rem + 2vw, 3.5rem);
  --text-display--line-height: 1.1;
  --text-display--font-weight: 700;

  --radius-*: initial;
  --radius-sm: 0.25rem;
  --radius-md: 0.5rem;
  --radius-lg: 1rem;
  --radius-full: 9999px;

  --shadow-*: initial;
  --shadow-sm: 0 1px 2px var(--color-shadow);
  --shadow-md: 0 4px 12px var(--color-shadow);
  --shadow-lg: 0 12px 32px var(--color-shadow);

  --breakpoint-*: initial;
  --breakpoint-sm: 40rem;
  --breakpoint-md: 48rem;
  --breakpoint-lg: 64rem;
  --breakpoint-xl: 80rem;

  --ease-standard: cubic-bezier(0.2, 0, 0, 1);
  --ease-exit: cubic-bezier(0.4, 0, 1, 1);
}

/* Non-namespaced tokens Tailwind does not generate utilities for */
:root {
  --motion-duration-fast: 150ms;
  --motion-duration-base: 250ms;
  --motion-duration-slow: 400ms;
  --z-dropdown: 100;
  --z-sticky: 200;
  --z-overlay: 300;
  --z-dialog: 400;
  --z-toast: 500;
  --size-header: 4rem;
  --size-target: 44px;
}

@layer base {
  :root {
    color-scheme: light dark;
    background: var(--color-surface);
    color: var(--color-on-surface);
  }
  :root[data-theme='light'] {
    color-scheme: light;
  }
  :root[data-theme='dark'] {
    color-scheme: dark;
  }

  @media (prefers-reduced-motion: reduce) {
    :root {
      --motion-duration-fast: 0ms;
      --motion-duration-base: 0ms;
      --motion-duration-slow: 0ms;
    }
  }
}
```

| Token namespace  | Generated utilities                              | Example                                           |
| ---------------- | ------------------------------------------------ | ------------------------------------------------- |
| `--color-*`      | `bg-*`, `text-*`, `border-*`, `ring-*`, `fill-*` | `bg-surface-raised text-on-surface border-border` |
| `--spacing`      | `p-*`, `m-*`, `gap-*`, `w-*`, `h-*`, `inset-*`   | `p-4 gap-2 ps-6`                                  |
| `--font-*`       | `font-*`                                         | `font-sans`                                       |
| `--text-*`       | `text-*` with paired line height and weight      | `text-title-md`                                   |
| `--radius-*`     | `rounded-*`                                      | `rounded-md`                                      |
| `--shadow-*`     | `shadow-*`                                       | `shadow-md`                                       |
| `--breakpoint-*` | `sm:`, `md:`, `lg:`, `xl:` variants              | `md:grid-cols-2`                                  |
| `--ease-*`       | `ease-*`                                         | `ease-standard`                                   |

Duration utilities have no theme namespace; use `duration-[var(--motion-duration-fast)]` or a `@utility motion-fast { transition-duration: var(--motion-duration-fast); }` declaration.

### Legacy browsers

`light-dark()` is Baseline 2024. When a browser target predates it, keep the same token names and duplicate the dark values in two blocks that must stay in sync: `@media (prefers-color-scheme: dark) { :root:not([data-theme='light']) { ... } }` for the `system` state and `:root[data-theme='dark'] { ... }` for the explicit choice. Both blocks live in `@layer base`, outside `@theme`, and still reach utilities because utilities read `var(--color-*)` at runtime; never use `@theme inline` for colors in that setup, because inlining bakes the light value into every utility.

### Dark variant

Tailwind's `dark:` variant defaults to `prefers-color-scheme`. Components should not need it (tokens already switch), but when a one-off is unavoidable, bind it to the attribute so `system`, `light`, and `dark` all behave:

```css
@custom-variant dark (&:where([data-theme='dark'], [data-theme='dark'] *));
```

---

## Breakpoints Without Tailwind

Custom properties cannot appear in `@media`. Keep breakpoints in one TypeScript module and in one CSS comment block that mirrors it.

```ts
// packages/ui/src/theme/breakpoints.ts
export const breakpoints = {
  sm: 640,
  md: 768,
  lg: 1024,
  xl: 1280,
} as const;

export type Breakpoint = keyof typeof breakpoints;

export function mediaQuery(breakpoint: Breakpoint): string {
  return `(min-width: ${breakpoints[breakpoint]}px)`;
}
```

```ts
// packages/ui/src/theme/useMediaQuery.ts
import { useSyncExternalStore } from 'react';

export function useMediaQuery(query: string): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const mql = window.matchMedia(query);
      mql.addEventListener('change', onChange);
      return () => mql.removeEventListener('change', onChange);
    },
    () => window.matchMedia(query).matches,
    () => false,
  );
}
```

```ts
// packages/ui/src/theme/breakpoints.test.ts
import { describe, expect, it } from 'vitest';
import { mediaQuery } from './breakpoints';

describe('mediaQuery', () => {
  it('builds a min-width query from the scale', () => {
    expect(mediaQuery('md')).toBe('(min-width: 768px)');
  });
});
```

Use container queries (`@container`) for component-level responsiveness; media breakpoints are for page layout only.
