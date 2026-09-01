# Theming — Components

Theming Radix and shadcn-style components with tokens, variant tokens with `class-variance-authority`, the full `ThemeProvider` test, a theme toggle, and the Storybook theme toolbar.

---

## Rules

| Rule                                                        | Detail                                                                                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Component tokens alias semantic tokens on the root selector | `.button { --button-bg: var(--color-primary); }`                                                                                |
| Variants reassign component tokens only                     | `.button--danger { --button-bg: var(--color-danger); }`; no duplicated layout rules                                             |
| CVA maps props to variant classes, never to inline colors   | `cva()` output is a class string; colors stay in CSS                                                                            |
| Radix data attributes drive state styling                   | `[data-state='open']`, `[data-highlighted]`, `[data-disabled]`; never `className` swaps from JavaScript                         |
| Portaled content inherits tokens from `:root`               | Tokens live on `:root`, so `Dialog.Portal` and `DropdownMenu.Portal` content is themed without wrapping                         |
| shadcn-style components receive the same token names        | Replace `--background`/`--foreground` with `--color-surface`/`--color-on-surface` in `@theme`; do not maintain two vocabularies |

---

## CVA Variants

```tsx
// packages/ui/src/Badge.tsx
import { cva, type VariantProps } from 'class-variance-authority';
import type { ComponentProps } from 'react';

const badge = cva('badge', {
  variants: {
    tone: { neutral: 'badge--neutral', primary: 'badge--primary', success: 'badge--success', danger: 'badge--danger' },
    size: { sm: 'badge--sm', md: 'badge--md' },
  },
  defaultVariants: { tone: 'neutral', size: 'md' },
});

export type BadgeProps = ComponentProps<'span'> & VariantProps<typeof badge>;

export function Badge({ tone, size, className, ...rest }: BadgeProps) {
  return <span className={badge({ tone, size, className })} {...rest} />;
}
```

```css
/* packages/ui/src/Badge.css */
.badge {
  --badge-bg: var(--color-surface-raised);
  --badge-fg: var(--color-on-surface);
  display: inline-flex;
  align-items: center;
  gap: var(--space-1);
  padding-block: var(--space-1);
  padding-inline: var(--space-2);
  border-radius: var(--radius-full);
  background: var(--badge-bg);
  color: var(--badge-fg);
  font: var(--font-weight-semibold) var(--text-label) / var(--leading-label) var(--font-family-sans);
}
.badge--primary { --badge-bg: var(--color-primary-subtle); --badge-fg: var(--color-on-primary-subtle); }
.badge--success { --badge-bg: var(--color-success); --badge-fg: var(--color-on-primary); }
.badge--danger { --badge-bg: var(--color-danger); --badge-fg: var(--color-on-danger); }
.badge--sm { padding-block: 0; font-size: var(--text-body-sm); }
```

Tailwind equivalent, same props:

```tsx
const badge = cva('inline-flex items-center gap-1 rounded-full px-2 py-1 text-label font-semibold', {
  variants: {
    tone: {
      neutral: 'bg-surface-raised text-on-surface',
      primary: 'bg-primary-subtle text-on-primary-subtle',
      success: 'bg-success text-on-primary',
      danger: 'bg-danger text-on-danger',
    },
    size: { sm: 'py-0 text-body-sm', md: '' },
  },
  defaultVariants: { tone: 'neutral', size: 'md' },
});
```

```tsx
// packages/ui/src/Badge.test.tsx
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Badge } from './Badge';

describe('Badge', () => {
  it('applies default variants', () => {
    render(<Badge>Draft</Badge>);
    expect(screen.getByText('Draft')).toHaveClass('badge', 'badge--neutral', 'badge--md');
  });

  it('applies requested variants and merges className', () => {
    render(<Badge tone="danger" size="sm" className="ms-2">Failed</Badge>);
    expect(screen.getByText('Failed')).toHaveClass('badge--danger', 'badge--sm', 'ms-2');
  });
});
```

---

## Radix Primitives

Style Radix parts through their data attributes; every color is a token.

```tsx
// packages/ui/src/Select.tsx
import * as SelectPrimitive from '@radix-ui/react-select';
import type { ReactNode } from 'react';

type SelectOption = { value: string; label: string };

type SelectProps = {
  label: string;
  value: string;
  onValueChange: (value: string) => void;
  options: ReadonlyArray<SelectOption>;
  placeholder?: string;
  icon?: ReactNode;
};

export function Select({ label, value, onValueChange, options, placeholder, icon }: SelectProps) {
  return (
    <SelectPrimitive.Root value={value} onValueChange={onValueChange}>
      <SelectPrimitive.Trigger className="select-trigger" aria-label={label}>
        <SelectPrimitive.Value placeholder={placeholder} />
        <SelectPrimitive.Icon aria-hidden="true">{icon}</SelectPrimitive.Icon>
      </SelectPrimitive.Trigger>
      <SelectPrimitive.Portal>
        <SelectPrimitive.Content className="select-content" position="popper" sideOffset={4}>
          <SelectPrimitive.Viewport>
            {options.map((option) => (
              <SelectPrimitive.Item key={option.value} value={option.value} className="select-item">
                <SelectPrimitive.ItemText>{option.label}</SelectPrimitive.ItemText>
              </SelectPrimitive.Item>
            ))}
          </SelectPrimitive.Viewport>
        </SelectPrimitive.Content>
      </SelectPrimitive.Portal>
    </SelectPrimitive.Root>
  );
}
```

```css
/* packages/ui/src/Select.css */
.select-trigger {
  --select-bg: var(--color-surface);
  --select-border: var(--color-border);
  display: inline-flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  min-block-size: var(--size-target);
  padding-inline: var(--space-3);
  border: 1px solid var(--select-border);
  border-radius: var(--radius-sm);
  background: var(--select-bg);
  color: var(--color-on-surface);
  transition: border-color var(--motion-duration-fast) var(--motion-easing-standard);
}
.select-trigger:hover { --select-border: var(--color-border-strong); }
.select-trigger:focus-visible { outline: 2px solid var(--color-focus-ring); outline-offset: 2px; }
.select-trigger[data-placeholder] { color: var(--color-on-surface-muted); }
.select-trigger[data-disabled] { color: var(--color-on-surface-disabled); }

.select-content {
  z-index: var(--z-dropdown);
  min-inline-size: var(--radix-select-trigger-width);
  padding: var(--space-1);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface-raised);
  box-shadow: var(--shadow-md);
  animation: select-enter var(--motion-duration-base) var(--motion-easing-standard);
}
.select-item {
  display: flex;
  align-items: center;
  min-block-size: var(--size-target);
  padding-inline: var(--space-3);
  border-radius: var(--radius-sm);
  color: var(--color-on-surface);
  outline: none;
}
.select-item[data-highlighted] { background: var(--color-primary-subtle); color: var(--color-on-primary-subtle); }
.select-item[data-state='checked'] { font-weight: var(--font-weight-semibold); }

@keyframes select-enter {
  from { opacity: 0; transform: translateY(calc(-1 * var(--space-1))); }
  to { opacity: 1; transform: none; }
}
```

`--radix-select-trigger-width` is provided by Radix; the animation reads `--motion-duration-base`, so it collapses to `0ms` under reduced motion with no JavaScript.

---

## shadcn-style Components

shadcn generates components that read `--background`, `--foreground`, `--primary`, and so on through Tailwind. Rename at the `@theme` boundary once so generated components use the project vocabulary:

```css
@theme {
  --color-background: var(--color-surface);
  --color-foreground: var(--color-on-surface);
  --color-card: var(--color-surface-raised);
  --color-card-foreground: var(--color-on-surface);
  --color-muted-foreground: var(--color-on-surface-muted);
  --color-destructive: var(--color-danger);
  --color-ring: var(--color-focus-ring);
  --color-input: var(--color-border);
}
```

Aliases are temporary: migrate generated components to the semantic names during review, then delete the aliases. Two vocabularies in one codebase is the anti-pattern.

---

## ThemeProvider Test

```tsx
// packages/ui/src/theme/ThemeProvider.test.tsx
import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ThemeProvider, useTheme } from './ThemeProvider';

type ChangeListener = (event: MediaQueryListEvent) => void;

function stubMatchMedia(initialMatches: boolean) {
  const listeners = new Set<ChangeListener>();
  const mql = {
    matches: initialMatches,
    media: '(prefers-color-scheme: dark)',
    addEventListener: (_type: string, listener: ChangeListener) => listeners.add(listener),
    removeEventListener: (_type: string, listener: ChangeListener) => listeners.delete(listener),
  };
  vi.stubGlobal('matchMedia', vi.fn(() => mql as unknown as MediaQueryList));
  return {
    setMatches(matches: boolean) {
      mql.matches = matches;
      for (const listener of listeners) listener({ matches } as MediaQueryListEvent);
    },
  };
}

function ThemeProbe() {
  const { preference, resolved, setPreference } = useTheme();
  return (
    <>
      <output>{`${preference} / ${resolved}`}</output>
      <button type="button" onClick={() => setPreference('dark')}>Use dark</button>
      <button type="button" onClick={() => setPreference('light')}>Use light</button>
      <button type="button" onClick={() => setPreference('system')}>Use system</button>
    </>
  );
}

describe('ThemeProvider', () => {
  beforeEach(() => {
    localStorage.clear();
    delete document.documentElement.dataset['theme'];
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('defaults to system and follows the media query', () => {
    stubMatchMedia(true);
    render(<ThemeProvider><ThemeProbe /></ThemeProvider>);

    expect(screen.getByRole('status')).toHaveTextContent('system / dark');
    expect(document.documentElement.dataset['theme']).toBeUndefined();
  });

  it('reads a persisted preference', () => {
    stubMatchMedia(false);
    localStorage.setItem('theme', 'dark');
    render(<ThemeProvider><ThemeProbe /></ThemeProvider>);

    expect(screen.getByRole('status')).toHaveTextContent('dark / dark');
    expect(document.documentElement.dataset['theme']).toBe('dark');
  });

  it('applies an explicit preference and persists it', async () => {
    stubMatchMedia(false);
    const user = userEvent.setup();
    render(<ThemeProvider><ThemeProbe /></ThemeProvider>);

    await user.click(screen.getByRole('button', { name: 'Use dark' }));

    expect(document.documentElement.dataset['theme']).toBe('dark');
    expect(localStorage.getItem('theme')).toBe('dark');
    expect(screen.getByRole('status')).toHaveTextContent('dark / dark');
  });

  it('returns to system and clears storage', async () => {
    const media = stubMatchMedia(false);
    localStorage.setItem('theme', 'dark');
    const user = userEvent.setup();
    render(<ThemeProvider><ThemeProbe /></ThemeProvider>);

    await user.click(screen.getByRole('button', { name: 'Use system' }));

    expect(localStorage.getItem('theme')).toBeNull();
    expect(document.documentElement.dataset['theme']).toBeUndefined();
    expect(screen.getByRole('status')).toHaveTextContent('system / light');

    act(() => media.setMatches(true));
    expect(screen.getByRole('status')).toHaveTextContent('system / dark');
  });

  it('ignores invalid stored values', () => {
    stubMatchMedia(false);
    localStorage.setItem('theme', 'purple');
    render(<ThemeProvider><ThemeProbe /></ThemeProvider>);
    expect(screen.getByRole('status')).toHaveTextContent('system / light');
  });

  it('throws when useTheme is used outside the provider', () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    expect(() => render(<ThemeProbe />)).toThrow('useTheme must be used within ThemeProvider');
  });
});
```

`<output>` has the implicit `status` role, so the probe is queried by role without a test id.

---

## Theme Toggle

```tsx
// packages/ui/src/theme/ThemeToggle.tsx
import { useTheme, type ThemePreference } from './ThemeProvider';

type ThemeToggleProps = {
  label: string;
  optionLabels: Record<ThemePreference, string>;
};

const preferences: ReadonlyArray<ThemePreference> = ['light', 'dark', 'system'];

export function ThemeToggle({ label, optionLabels }: ThemeToggleProps) {
  const { preference, setPreference } = useTheme();

  return (
    <fieldset className="theme-toggle">
      <legend>{label}</legend>
      {preferences.map((option) => (
        <label key={option}>
          <input
            type="radio"
            name="theme"
            value={option}
            checked={preference === option}
            onChange={() => setPreference(option)}
          />
          {optionLabels[option]}
        </label>
      ))}
    </fieldset>
  );
}
```

Labels arrive as props so `packages/ui` stays free of the i18n runtime. A radio group exposes all three states to screen readers; an icon-only cycle button hides the `system` state and fails 4.1.2 without extra ARIA.

---

## Storybook Theme Toolbar

```ts
// .storybook/preview.ts
import type { Decorator, Preview } from '@storybook/react';
import '../packages/ui/src/styles/tokens.css';

const withTheme: Decorator = (Story, context) => {
  const theme = context.globals['theme'];
  if (theme === 'light' || theme === 'dark') document.documentElement.dataset['theme'] = theme;
  else delete document.documentElement.dataset['theme'];
  return Story();
};

const preview: Preview = {
  decorators: [withTheme],
  globalTypes: {
    theme: {
      description: 'Color theme',
      toolbar: { title: 'Theme', items: ['light', 'dark', 'system'] },
    },
  },
  initialGlobals: { theme: 'light' },
};

export default preview;
```

Pair with a Storybook test runner or Chromatic modes for `light` and `dark` so every story is visually checked in both themes.
