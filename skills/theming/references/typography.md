# Theming — Typography

Type scale tokens with paired line heights, font loading, fluid display sizes, and the `Text` component that keeps raw `font-size` out of feature code.

---

## Scale

Sizes are `rem` so user zoom and browser font settings apply (WCAG 1.4.4). Every size ships with a line height; body text never drops below 1.5.

| Role       | `--text-*`                          | `--leading-*` | Weight | Use                                  |
| ---------- | ----------------------------------- | ------------- | ------ | ------------------------------------ |
| `display`  | `clamp(2.5rem, 2rem + 2vw, 3.5rem)` | `1.1`         | 700    | Marketing hero, one per page at most |
| `title-lg` | `2rem` (32px)                       | `2.5rem`      | 600    | Page `h1`                            |
| `title-md` | `1.5rem` (24px)                     | `2rem`        | 600    | Section `h2`                         |
| `title-sm` | `1.25rem` (20px)                    | `1.75rem`     | 600    | Card and dialog titles, `h3`         |
| `body-lg`  | `1.125rem` (18px)                   | `1.75rem`     | 400    | Lead paragraphs                      |
| `body-md`  | `1rem` (16px)                       | `1.5rem`      | 400    | Default body, inputs, buttons        |
| `body-sm`  | `0.875rem` (14px)                   | `1.25rem`     | 400    | Secondary text, table cells          |
| `label`    | `0.875rem` (14px)                   | `1.25rem`     | 600    | Form labels, tabs, badges            |
| `code`     | `0.875rem` (14px)                   | `1.25rem`     | 400    | Inline and block code, mono family   |

Nothing below 14px except legal fine print, and never for interactive text. Heading level (`h1`-`h3`) is chosen by document structure; the visual role is chosen separately with a class.

```css
/* packages/ui/src/styles/tokens.css (typography section) */
:root {
  --font-family-sans: 'Inter Variable', system-ui, -apple-system, 'Segoe UI', sans-serif;
  --font-family-mono: 'JetBrains Mono', ui-monospace, SFMono-Regular, monospace;

  --font-weight-regular: 400;
  --font-weight-semibold: 600;
  --font-weight-bold: 700;

  --text-display: clamp(2.5rem, 2rem + 2vw, 3.5rem);
  --leading-display: 1.1;
  --text-title-lg: 2rem;
  --leading-title-lg: 2.5rem;
  --text-title-md: 1.5rem;
  --leading-title-md: 2rem;
  --text-title-sm: 1.25rem;
  --leading-title-sm: 1.75rem;
  --text-body-lg: 1.125rem;
  --leading-body-lg: 1.75rem;
  --text-body-md: 1rem;
  --leading-body-md: 1.5rem;
  --text-body-sm: 0.875rem;
  --leading-body-sm: 1.25rem;
  --text-label: 0.875rem;
  --leading-label: 1.25rem;

  --tracking-tight: -0.01em;
  --tracking-wide: 0.02em;
  --measure: 65ch;
}
```

---

## Base Styles

```css
/* packages/ui/src/styles/base.css */
html {
  font-family: var(--font-family-sans);
  font-size: 100%; /* never a fixed px; respects user settings */
  line-height: var(--leading-body-md);
  -webkit-font-smoothing: antialiased;
  text-size-adjust: 100%;
}

body {
  margin: 0;
  background: var(--color-surface);
  color: var(--color-on-surface);
  font-size: var(--text-body-md);
}

p,
li {
  max-inline-size: var(--measure);
}

code,
kbd,
pre {
  font-family: var(--font-family-mono);
  font-size: var(--text-body-sm);
}
```

`max-inline-size: 65ch` keeps line length under 80 characters (WCAG 1.4.8) without a container hack.

---

## Text Component

The `Text` component is the only place `--text-*` tokens are read in application code. It separates the semantic element from the visual role.

```tsx
// packages/ui/src/Text.tsx
import type { ComponentProps, ElementType, ReactNode } from 'react';

export type TextRole = 'display' | 'title-lg' | 'title-md' | 'title-sm' | 'body-lg' | 'body-md' | 'body-sm' | 'label';
export type TextTone = 'default' | 'muted' | 'danger';

type TextElement = 'h1' | 'h2' | 'h3' | 'h4' | 'p' | 'span' | 'label' | 'div';

type TextProps<E extends TextElement> = Omit<ComponentProps<E>, 'className'> & {
  as?: E;
  role?: TextRole;
  tone?: TextTone;
  className?: string;
  children: ReactNode;
};

const defaultElement: Record<TextRole, TextElement> = {
  display: 'h1',
  'title-lg': 'h1',
  'title-md': 'h2',
  'title-sm': 'h3',
  'body-lg': 'p',
  'body-md': 'p',
  'body-sm': 'p',
  label: 'span',
};

export function Text<E extends TextElement = 'p'>({ as, role = 'body-md', tone = 'default', className, ...rest }: TextProps<E>) {
  const Component: ElementType = as ?? defaultElement[role];
  const classes = [`text-${role}`, tone === 'default' ? '' : `text-tone-${tone}`, className ?? ''].filter(Boolean).join(' ');
  return <Component className={classes} {...rest} />;
}
```

```css
/* packages/ui/src/Text.css */
.text-display { font: var(--font-weight-bold) var(--text-display) / var(--leading-display) var(--font-family-sans); letter-spacing: var(--tracking-tight); }
.text-title-lg { font: var(--font-weight-semibold) var(--text-title-lg) / var(--leading-title-lg) var(--font-family-sans); letter-spacing: var(--tracking-tight); }
.text-title-md { font: var(--font-weight-semibold) var(--text-title-md) / var(--leading-title-md) var(--font-family-sans); }
.text-title-sm { font: var(--font-weight-semibold) var(--text-title-sm) / var(--leading-title-sm) var(--font-family-sans); }
.text-body-lg { font: var(--font-weight-regular) var(--text-body-lg) / var(--leading-body-lg) var(--font-family-sans); }
.text-body-md { font: var(--font-weight-regular) var(--text-body-md) / var(--leading-body-md) var(--font-family-sans); }
.text-body-sm { font: var(--font-weight-regular) var(--text-body-sm) / var(--leading-body-sm) var(--font-family-sans); }
.text-label { font: var(--font-weight-semibold) var(--text-label) / var(--leading-label) var(--font-family-sans); letter-spacing: var(--tracking-wide); }
.text-tone-muted { color: var(--color-on-surface-muted); }
.text-tone-danger { color: var(--color-danger); }
```

```tsx
// packages/ui/src/Text.test.tsx
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Text } from './Text';

describe('Text', () => {
  it('picks the element from the role', () => {
    render(<Text role="title-md">Section</Text>);
    expect(screen.getByRole('heading', { level: 2, name: 'Section' })).toHaveClass('text-title-md');
  });

  it('separates element from visual role', () => {
    render(<Text as="h3" role="title-lg">Big but h3</Text>);
    expect(screen.getByRole('heading', { level: 3 })).toHaveClass('text-title-lg');
  });

  it('applies tone classes only when not default', () => {
    render(<Text tone="muted">Muted</Text>);
    expect(screen.getByText('Muted')).toHaveClass('text-body-md', 'text-tone-muted');
    render(<Text>Plain</Text>);
    expect(screen.getByText('Plain')).not.toHaveClass('text-tone-muted');
  });
});
```

With Tailwind, `text-title-md` is generated from `--text-title-md` plus its `--line-height` and `--font-weight` companions, so the CSS file above is unnecessary; the component still exists to bind role to element.

---

## Font Loading

```bash
pnpm add @fontsource-variable/inter
```

```ts
// apps/web/src/main.tsx (first import)
import '@fontsource-variable/inter';
```

| Rule                                       | Reason                                                                         |
| ------------------------------------------ | ------------------------------------------------------------------------------ |
| Self-host through `@fontsource-variable/*` | No third-party request, no consent banner, deterministic caching               |
| One variable font per family               | One file covers every weight; no per-weight requests                           |
| `font-display: swap` (Fontsource default)  | Text renders immediately in the fallback                                       |
| Match fallback metrics with `size-adjust`  | Prevents layout shift when the web font arrives                                |
| Preload only the primary Latin subset      | `<link rel="preload" as="font" type="font/woff2" crossorigin>` in `index.html` |

```css
@font-face {
  font-family: 'Inter Fallback';
  src: local('Arial');
  size-adjust: 107%;
  ascent-override: 90%;
  descent-override: 22%;
  line-gap-override: 0%;
}
:root {
  --font-family-sans: 'Inter Variable', 'Inter Fallback', system-ui, sans-serif;
}
```

Next.js: use `next/font/local` or `next/font/google` and pass `variable: '--font-family-sans'`; it generates the fallback overrides automatically.

---

## Fluid Type

Only `display` is fluid. Body and title sizes stay fixed so paired line heights, spacing rhythm, and contrast checks remain predictable.

```css
--text-display: clamp(2.5rem, 2rem + 2vw, 3.5rem);
```

The `rem` term in the middle keeps zoom working; a pure `vw` value would ignore browser zoom and fail WCAG 1.4.4.
