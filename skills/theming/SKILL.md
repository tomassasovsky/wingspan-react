---
name: react-theming
description: Best practices for theming React applications with design tokens as CSS custom properties, semantic color layers, light and dark mode via data-theme with a prefers-color-scheme fallback, Tailwind CSS v4 @theme mapping, a ThemeProvider with persisted preference, and token-driven component styling. Use when creating, modifying, or reviewing tokens, color palettes, dark mode, spacing or typography scales, breakpoints, motion tokens, ThemeProvider, or component variants.
allowed-tools: Read Glob Grep
---

# Theming

Design tokens as CSS custom properties are the single source of truth for color, spacing, typography, radii, shadows, and motion; components consume semantic tokens, `data-theme` switches `color-scheme`, and Tailwind CSS v4 maps the same tokens into utilities through `@theme`.

---

## Core Standards

Apply these standards to ALL theming work:

- **Tokens are CSS custom properties defined once in `tokens.css`** — no color, size, or duration literals anywhere else
- **Components consume semantic tokens, never primitives** — `var(--color-primary)`, not `var(--palette-blue-600)` or `#2563eb`
- **Three token layers: primitive, semantic, component** — primitives name values (`--palette-blue-600`), semantics name intent (`--color-primary`), component tokens alias semantics for one component (`--button-bg`)
- **Light and dark share one semantic name** — every color token is declared once as `light-dark(light, dark)`; components contain zero theme conditionals
- **`data-theme` sets `color-scheme`, `prefers-color-scheme` is the fallback** — `:root { color-scheme: light dark }`, `[data-theme='dark'] { color-scheme: dark }`; an inline no-flash script applies the stored preference before first paint
- **Preference has three states: `light`, `dark`, `system`** — `system` removes `data-theme` and lets the media query decide
- **Semantic colors come in surface/on-surface pairs** — `--color-primary` with `--color-on-primary`; contrast is verified per pair in both themes
- **Spacing uses a 4px base scale** — `--space-1` through `--space-16`; no arbitrary pixel values in components
- **Typography is a named scale with paired line heights** — `--text-body-md` with `--leading-body-md`; no raw `font-size`
- **Breakpoints live in one place** — `@theme --breakpoint-*` with Tailwind, otherwise `breakpoints.ts` plus `useMediaQuery`; custom properties cannot be used inside `@media`
- **Motion tokens collapse to `0ms` under `prefers-reduced-motion`** — every transition and animation reads `--motion-duration-*`
- **With Tailwind v4, the `@theme` block is the semantic layer** — utilities such as `bg-primary` and `p-4` read the same variables; never maintain a parallel `:root` copy
- **`ThemeProvider` owns preference state and DOM sync; `useTheme` is the only consumer API** — no component touches `localStorage` or `document.documentElement`
- **Every provider, hook, and themed component ships with a test** — `vitest` + `@testing-library/react`

The full catalog, naming convention, and layer rules are in [references/tokens.md](references/tokens.md).

---

## tokens.css

```css
/* packages/ui/src/styles/tokens.css */
:root {
  /* data-theme overrides this; without it the OS preference applies */
  color-scheme: light dark;

  /* Primitives: never read by components */
  --palette-blue-400: oklch(72% 0.16 260);
  --palette-blue-600: oklch(55% 0.2 260);
  --palette-blue-700: oklch(48% 0.2 260);
  --palette-neutral-0: oklch(100% 0 0);
  --palette-neutral-100: oklch(96% 0.005 260);
  --palette-neutral-300: oklch(85% 0.01 260);
  --palette-neutral-600: oklch(52% 0.02 260);
  --palette-neutral-800: oklch(28% 0.02 260);
  --palette-neutral-900: oklch(20% 0.02 260);
  --palette-neutral-950: oklch(14% 0.02 260);
  --palette-red-400: oklch(70% 0.19 25);
  --palette-red-600: oklch(55% 0.22 25);

  /* Semantic: color as light-dark(light, dark) */
  --color-surface: light-dark(var(--palette-neutral-0), var(--palette-neutral-950));
  --color-surface-raised: light-dark(var(--palette-neutral-100), var(--palette-neutral-900));
  --color-on-surface: light-dark(var(--palette-neutral-900), var(--palette-neutral-100));
  --color-on-surface-muted: light-dark(var(--palette-neutral-600), var(--palette-neutral-300));
  --color-border: light-dark(var(--palette-neutral-300), var(--palette-neutral-800));
  --color-primary: light-dark(var(--palette-blue-600), var(--palette-blue-400));
  --color-primary-hover: light-dark(var(--palette-blue-700), var(--palette-blue-600));
  --color-on-primary: light-dark(var(--palette-neutral-0), var(--palette-neutral-950));
  --color-danger: light-dark(var(--palette-red-600), var(--palette-red-400));
  --color-on-danger: light-dark(var(--palette-neutral-0), var(--palette-neutral-950));
  --color-focus-ring: light-dark(var(--palette-blue-600), var(--palette-blue-400));
  --color-shadow: light-dark(oklch(0% 0 0 / 0.12), oklch(0% 0 0 / 0.5));

  /* Semantic: spacing (4px base) */
  --space-1: 0.25rem;
  --space-2: 0.5rem;
  --space-3: 0.75rem;
  --space-4: 1rem;
  --space-6: 1.5rem;
  --space-8: 2rem;
  --space-12: 3rem;
  --space-16: 4rem;

  /* Semantic: typography */
  --font-family-sans: 'Inter Variable', system-ui, sans-serif;
  --font-weight-regular: 400;
  --font-weight-semibold: 600;
  --text-body-sm: 0.875rem;
  --leading-body-sm: 1.25rem;
  --text-body-md: 1rem;
  --leading-body-md: 1.5rem;
  --text-title-lg: 2rem;
  --leading-title-lg: 2.5rem;

  /* Semantic: shape, elevation, motion */
  --radius-sm: 0.25rem;
  --radius-md: 0.5rem;
  --shadow-sm: 0 1px 2px var(--color-shadow);
  --shadow-md: 0 4px 12px var(--color-shadow);
  --motion-duration-fast: 150ms;
  --motion-duration-base: 250ms;
  --motion-easing-standard: cubic-bezier(0.2, 0, 0, 1);
}

:root[data-theme='light'] { color-scheme: light; }
:root[data-theme='dark'] { color-scheme: dark; }

@media (prefers-reduced-motion: reduce) {
  :root {
    --motion-duration-fast: 0ms;
    --motion-duration-base: 0ms;
  }
}
```

`light-dark()` resolves on the element that reads the token, against that element's `color-scheme`, so portaled content and nested theme overrides (`<section data-theme="dark">`) work without extra rules. Non-color tokens (spacing, motion, radii) are theme-independent by design.

---

## No-Flash Script

Inline in `index.html` (Vite) or the root `layout.tsx` (Next.js) before any stylesheet-dependent paint:

```html
<script>
  (function () {
    try {
      var theme = localStorage.getItem('theme');
      if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme;
    } catch (_) {}
  })();
</script>
```

In Next.js render it with `dangerouslySetInnerHTML` inside `<head>` and add `suppressHydrationWarning` to `<html>`.

---

## ThemeProvider and useTheme

```tsx
// packages/ui/src/theme/ThemeProvider.tsx
import { createContext, useContext, useEffect, useMemo, useSyncExternalStore, type ReactNode } from 'react';

export type ThemePreference = 'light' | 'dark' | 'system';
export type ResolvedTheme = 'light' | 'dark';

const STORAGE_KEY = 'theme';
const DARK_QUERY = '(prefers-color-scheme: dark)';
const listeners = new Set<() => void>();

function isPreference(value: unknown): value is ThemePreference {
  return value === 'light' || value === 'dark' || value === 'system';
}

function readPreference(): ThemePreference {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return isPreference(stored) ? stored : 'system';
  } catch {
    return 'system';
  }
}

function writePreference(preference: ThemePreference) {
  try {
    if (preference === 'system') localStorage.removeItem(STORAGE_KEY);
    else localStorage.setItem(STORAGE_KEY, preference);
  } catch {
    // Storage unavailable; the preference lives for this session only.
  }
  for (const listener of listeners) listener();
}

function subscribePreference(onChange: () => void) {
  listeners.add(onChange);
  window.addEventListener('storage', onChange);
  return () => {
    listeners.delete(onChange);
    window.removeEventListener('storage', onChange);
  };
}

function subscribeSystem(onChange: () => void) {
  const mql = window.matchMedia(DARK_QUERY);
  mql.addEventListener('change', onChange);
  return () => mql.removeEventListener('change', onChange);
}

const getSystemTheme = (): ResolvedTheme => (window.matchMedia(DARK_QUERY).matches ? 'dark' : 'light');

type ThemeContextValue = {
  preference: ThemePreference;
  resolved: ResolvedTheme;
  setPreference: (preference: ThemePreference) => void;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: ReactNode }) {
  const preference = useSyncExternalStore(subscribePreference, readPreference, () => 'system');
  const system = useSyncExternalStore(subscribeSystem, getSystemTheme, () => 'light');
  const resolved: ResolvedTheme = preference === 'system' ? system : preference;

  useEffect(() => {
    const root = document.documentElement;
    if (preference === 'system') delete root.dataset['theme'];
    else root.dataset['theme'] = preference;
  }, [preference]);

  const value = useMemo<ThemeContextValue>(
    () => ({ preference, resolved, setPreference: writePreference }),
    [preference, resolved],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const context = useContext(ThemeContext);
  if (!context) throw new Error('useTheme must be used within ThemeProvider');
  return context;
}
```

`useSyncExternalStore` with server snapshots (`'system'`, `'light'`) keeps the provider SSR-safe; the no-flash script has already applied the attribute, so the first client paint matches. The matching `ThemeProvider.test.tsx` (default, persisted, explicit, system-change, invalid-storage, and missing-provider cases with a stubbed `matchMedia`), the theme toggle, and the Storybook toolbar are in [references/components.md](references/components.md).

---

## Tailwind CSS v4

When Tailwind is present, declare semantic tokens inside `@theme` so utilities and `var()` reads share one definition. `light-dark()` works inside `@theme` because utilities reference `var(--color-primary)` on the element and resolve it against that element's `color-scheme`.

```css
/* apps/web/src/app.css */
@import 'tailwindcss';
@import '@acme/ui/styles/primitives.css';

@theme {
  --color-*: initial;
  --color-surface: light-dark(var(--palette-neutral-0), var(--palette-neutral-950));
  --color-on-surface: light-dark(var(--palette-neutral-900), var(--palette-neutral-100));
  --color-border: light-dark(var(--palette-neutral-300), var(--palette-neutral-800));
  --color-primary: light-dark(var(--palette-blue-600), var(--palette-blue-400));
  --color-primary-hover: light-dark(var(--palette-blue-700), var(--palette-blue-600));
  --color-on-primary: light-dark(var(--palette-neutral-0), var(--palette-neutral-950));
  --color-focus-ring: light-dark(var(--palette-blue-600), var(--palette-blue-400));

  --spacing: 0.25rem;
  --font-sans: 'Inter Variable', system-ui, sans-serif;
  --text-body-md: 1rem;
  --text-body-md--line-height: 1.5rem;
  --radius-md: 0.5rem;
  --shadow-sm: 0 1px 2px light-dark(oklch(0% 0 0 / 0.12), oklch(0% 0 0 / 0.5));
  --breakpoint-md: 48rem;
  --ease-standard: cubic-bezier(0.2, 0, 0, 1);
}

@layer base {
  :root { color-scheme: light dark; }
  :root[data-theme='light'] { color-scheme: light; }
  :root[data-theme='dark'] { color-scheme: dark; }
}
```

`--color-*: initial` removes Tailwind's default palette so `bg-blue-500` does not compile; only semantic utilities (`bg-primary`, `text-on-surface`, `border-border`) exist. Bind the `dark:` variant to the attribute with `@custom-variant dark (&:where([data-theme='dark'], [data-theme='dark'] *))` for the rare one-off. The complete `@theme` block (every semantic color, the type scale, radii, shadows, breakpoints), motion and z-index tokens, the legacy fallback without `light-dark()`, and breakpoints without Tailwind are in [references/tokens.md](references/tokens.md).

---

## Themed Component

```tsx
// packages/ui/src/Button.tsx
import { cva, type VariantProps } from 'class-variance-authority';
import type { ComponentProps } from 'react';

const button = cva('button', {
  variants: {
    variant: { primary: 'button--primary', secondary: 'button--secondary', danger: 'button--danger' },
    size: { sm: 'button--sm', md: 'button--md' },
  },
  defaultVariants: { variant: 'primary', size: 'md' },
});

export type ButtonProps = ComponentProps<'button'> & VariantProps<typeof button>;

export function Button({ variant, size, type = 'button', className, ...rest }: ButtonProps) {
  return <button type={type} className={button({ variant, size, className })} {...rest} />;
}
```

```css
/* packages/ui/src/Button.css */
.button {
  --button-bg: var(--color-primary);
  --button-fg: var(--color-on-primary);
  --button-bg-hover: var(--color-primary-hover);
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  min-block-size: 44px;
  padding-inline: var(--space-4);
  border-radius: var(--radius-md);
  background: var(--button-bg);
  color: var(--button-fg);
  font: var(--font-weight-semibold) var(--text-body-md) / var(--leading-body-md) var(--font-family-sans);
  transition: background-color var(--motion-duration-fast) var(--motion-easing-standard);
}
.button:hover { background: var(--button-bg-hover); }
.button:focus-visible { outline: 2px solid var(--color-focus-ring); outline-offset: 2px; }
.button--secondary { --button-bg: var(--color-surface-raised); --button-fg: var(--color-on-surface); --button-bg-hover: var(--color-border); }
.button--danger { --button-bg: var(--color-danger); --button-fg: var(--color-on-danger); }
.button--sm { min-block-size: 36px; padding-inline: var(--space-3); font-size: var(--text-body-sm); }
```

Variants only reassign component tokens; layout and typography are written once. The Tailwind equivalent (`bg-primary text-on-primary hover:bg-primary-hover`), Radix and shadcn theming, and the `Badge` test are in [references/components.md](references/components.md).

---

## Anti-Patterns

| Anti-Pattern                                                 | Problem                                        | Correct Approach                                        |
| ------------------------------------------------------------ | ---------------------------------------------- | ------------------------------------------------------- |
| `color: #333` in a component                                 | Invisible to theming; fails in dark mode       | `color: var(--color-on-surface)`                        |
| `var(--palette-blue-600)` in a component                     | Primitive bypasses semantics; dark mode breaks | `var(--color-primary)`                                  |
| `resolved === 'dark' ? darkStyles : lightStyles` in JSX      | Theme logic duplicated in every component      | `light-dark()` tokens; `data-theme` sets `color-scheme` |
| Separate `[data-theme='dark']` override blocks per token     | Two copies drift apart                         | One `light-dark(light, dark)` declaration per token     |
| Reading `localStorage` in `useEffect` to set theme           | Flash of wrong theme on load                   | Inline no-flash script before paint                     |
| Only `prefers-color-scheme`, no override                     | Users cannot choose                            | `data-theme` attribute plus `system` state              |
| `class="dark"` toggled by JavaScript only                    | OS fallback lost when storage is empty         | `:root { color-scheme: light dark }` plus `data-theme`  |
| `padding: 13px`                                              | Off the 4px scale                              | `var(--space-3)`                                        |
| `font-size: 15px`                                            | Off the type scale; no paired line height      | `var(--text-body-md)` with `var(--leading-body-md)`     |
| `bg-blue-500` in app code                                    | Raw palette leaks into components              | `--color-*: initial` and semantic utilities             |
| `transition: all 300ms`                                      | Ignores reduced motion; animates layout        | `var(--motion-duration-base)` on named properties       |
| `@media (min-width: var(--breakpoint-md))`                   | Custom properties do not work in media queries | Tailwind `--breakpoint-*` or `breakpoints.ts`           |
| Separate light and dark token names (`--color-primary-dark`) | Every component branches                       | Same name, both values inside `light-dark()`            |

---

## Additional Resources

- [Token catalog](references/tokens.md) — naming convention, primitive, semantic, and component layers, complete Tailwind `@theme` mapping, breakpoints and `useMediaQuery`
- [Typography](references/typography.md) — type scale, `Text` component and test, font loading, fluid sizing
- [Spacing](references/spacing.md) — 4px scale, `Stack` and `Inline` primitives with tests, density
- [Components](references/components.md) — CVA variant tokens, Radix and shadcn-style theming, `ThemeProvider` test, theme toggle, Storybook theme toolbar
- [Tailwind CSS v4 theme variables](https://tailwindcss.com/docs/theme)
- [CSS `light-dark()`](https://developer.mozilla.org/docs/Web/CSS/color_value/light-dark)
