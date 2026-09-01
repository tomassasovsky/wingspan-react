---
name: react-ui-package
description: Best practices for building the shared React component library in packages/ui. Covers design tokens as CSS custom properties with data-theme dark mode, component API conventions (ref as a prop, className merging, class-variance-authority variants), accessible primitives on Radix, barrel exports and the exports map, tsup library builds, Storybook 8 CSF3 stories with addon-a11y, and Testing Library tests for every component. Use when user says "create a ui package", "add a component to the design system", "build a component library", "add design tokens", "write a story", or "set up Storybook".
allowed-tools: Read Glob Grep Write Edit Bash
---

# UI Package

Best practices for `packages/ui`: a reusable, accessible React component library with tokens, variants, stories, and tests, consumed by every app in the workspace.

---

## Core Standards

Apply these standards to ALL UI package work:

- **Presentation only** — `packages/ui` imports nothing from `@acme/*-api-client`, `@acme/*-storage`, or `@acme/*-repository`; components render props
- **Tokens are CSS custom properties** — every color, radius, spacing, and font value is a `--ui-*` variable; dark mode is `[data-theme='dark']`, never a second stylesheet
- **Build on Radix Primitives** — dialogs, menus, popovers, tooltips, tabs, checkboxes, and selects compose `@radix-ui/react-*`; never rebuild focus management or ARIA wiring
- **One component per folder** — `src/components/<name>/{Name.tsx,Name.stories.tsx,Name.test.tsx,index.ts}`
- **`ref` is a prop** — React 19 function components receive `ref` in props; never `forwardRef`
- **Props extend the native element** — `ComponentPropsWithRef<'button'>` plus variant props; `className` is always accepted and merged with `cn()`
- **Variants via `class-variance-authority`** — `variant` and `size` are `cva` variants with `defaultVariants`; export the `VariantProps` type
- **Named exports only** — default exports appear only in `*.stories.tsx` and config files
- **Every component has a CSF3 story and a Testing Library test** — stories cover every variant and state; tests cover behavior, accessible names, and `vitest-axe`
- **100% coverage** — `coverage.thresholds` at 100 in `vitest.config.ts`
- **No app knowledge** — no routing, no query hooks, no domain models; a component that needs a `Todo` belongs in the app's feature folder

## Package Structure

```text
packages/ui/
├── .storybook/
│   ├── main.ts                   # react-vite framework, addon-a11y, Tailwind plugin
│   └── preview.tsx               # Imports styles, theme toolbar, a11y parameters
├── src/
│   ├── components/
│   │   ├── button/
│   │   │   ├── Button.tsx
│   │   │   ├── Button.stories.tsx
│   │   │   ├── Button.test.tsx
│   │   │   └── index.ts
│   │   ├── checkbox/
│   │   └── dialog/
│   ├── lib/
│   │   ├── cn.ts                 # clsx + tailwind-merge
│   │   └── cn.test.ts
│   ├── styles/
│   │   ├── theme.css             # Tokens: :root, [data-theme='dark'], @theme inline
│   │   └── storybook.css         # @import 'tailwindcss' + theme, for the catalog only
│   ├── test/setup.ts             # jest-dom + vitest-axe matchers
│   └── index.ts                  # Barrel
├── package.json
├── tsconfig.json
├── tsup.config.ts
└── vitest.config.ts
```

## Design Tokens

`src/styles/theme.css` is the single source of truth. Raw values live on `--ui-*` variables; `@theme inline` maps them to Tailwind utilities so `bg-primary` resolves to `var(--ui-color-primary)` at the element, which is what makes the `data-theme` override work.

```css
/* src/styles/theme.css */
:root {
  --ui-color-bg: oklch(99% 0 0);
  --ui-color-fg: oklch(20% 0.01 260);
  --ui-color-muted: oklch(95% 0.01 260);
  --ui-color-muted-fg: oklch(45% 0.02 260);
  --ui-color-border: oklch(88% 0.01 260);
  --ui-color-primary: oklch(55% 0.2 260);
  --ui-color-primary-fg: oklch(99% 0 0);
  --ui-color-danger: oklch(55% 0.22 25);
  --ui-color-danger-fg: oklch(99% 0 0);
  --ui-color-ring: oklch(65% 0.2 260);
  --ui-radius-md: 0.5rem;
  --ui-font-sans: 'Inter', ui-sans-serif, system-ui, sans-serif;
}

[data-theme='dark'] {
  --ui-color-bg: oklch(18% 0.01 260);
  --ui-color-fg: oklch(96% 0 0);
  --ui-color-muted: oklch(26% 0.01 260);
  --ui-color-muted-fg: oklch(70% 0.02 260);
  --ui-color-border: oklch(32% 0.01 260);
  --ui-color-primary: oklch(70% 0.18 260);
  --ui-color-primary-fg: oklch(15% 0.02 260);
  --ui-color-ring: oklch(75% 0.16 260);
}

@theme inline {
  --color-bg: var(--ui-color-bg);
  --color-fg: var(--ui-color-fg);
  --color-muted: var(--ui-color-muted);
  --color-muted-fg: var(--ui-color-muted-fg);
  --color-border: var(--ui-color-border);
  --color-primary: var(--ui-color-primary);
  --color-primary-fg: var(--ui-color-primary-fg);
  --color-danger: var(--ui-color-danger);
  --color-danger-fg: var(--ui-color-danger-fg);
  --color-ring: var(--ui-color-ring);
  --radius-md: var(--ui-radius-md);
  --font-sans: var(--ui-font-sans);
}
```

The consuming app owns Tailwind and scans the package source:

```css
/* apps/web/src/index.css */
@import 'tailwindcss';
@import '@acme/ui/theme.css';
@source '../../../packages/ui/src';
```

Toggle dark mode with `document.documentElement.dataset.theme = 'dark'`; components never branch on theme.

## Component API Conventions

| Concern       | Rule                                                                                                         |
| ------------- | ------------------------------------------------------------------------------------------------------------ |
| Props type    | `ComponentPropsWithRef<'button'> & VariantProps<typeof buttonVariants> & { ... }`, exported as `ButtonProps` |
| Booleans      | Native `disabled` first; `isLoading` and similar only for states the element lacks                           |
| Callbacks     | Native names (`onClick`, `onCheckedChange`); custom callbacks are `on<Event>`                                |
| Slots         | `leadingIcon`, `trailingIcon`, `children` typed as `ReactNode`                                               |
| Polymorphism  | `asChild` with `@radix-ui/react-slot`; never an `as` prop                                                    |
| `className`   | Always accepted, merged last with `cn(variants(...), className)`                                             |
| `ref`         | Arrives through `...props` from `ComponentPropsWithRef`; never `forwardRef`                                  |
| Defaults      | `type="button"` on buttons; `defaultVariants` in `cva`                                                       |
| Accessibility | Visible label or `aria-label` required; loading sets `aria-busy`; decorative icons are `aria-hidden`         |
| Exports       | Component, its props type, and `xVariants` when apps style links as buttons                                  |

### Pattern: variants with `class-variance-authority`

```tsx
import { Slot } from '@radix-ui/react-slot';
import { cva, type VariantProps } from 'class-variance-authority';
import type { ComponentPropsWithRef } from 'react';

import { cn } from '../../lib/cn';

export const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 rounded-md font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring disabled:pointer-events-none disabled:opacity-50',
  {
    variants: {
      variant: {
        primary: 'bg-primary text-primary-fg hover:bg-primary/90',
        outline: 'border border-border bg-transparent hover:bg-muted',
        ghost: 'hover:bg-muted',
        danger: 'bg-danger text-danger-fg hover:bg-danger/90',
      },
      size: { sm: 'h-8 px-3 text-sm', md: 'h-10 px-4 text-sm', lg: 'h-12 px-6 text-base' },
    },
    defaultVariants: { variant: 'primary', size: 'md' },
  },
);

export type ButtonProps = ComponentPropsWithRef<'button'> &
  VariantProps<typeof buttonVariants> & { asChild?: boolean; isLoading?: boolean };

export function Button({ className, variant, size, asChild = false, isLoading = false, disabled, type, ...props }: ButtonProps) {
  const Component = asChild ? Slot : 'button';
  return (
    <Component
      className={cn(buttonVariants({ variant, size }), className)}
      disabled={disabled === true || isLoading}
      aria-busy={isLoading || undefined}
      type={asChild ? undefined : (type ?? 'button')}
      {...props}
    />
  );
}
```

See [references/component-template.md](references/component-template.md) for the complete `Button` with spinner and icon slots, the `cn` helper, its story, its test, and the barrel entry.

### Pattern: accessible primitive on Radix

Wrap the Radix parts, apply tokens, and make the accessibility parts mandatory in the API.

```tsx
// src/components/dialog/Dialog.tsx (excerpt)
export type DialogContentProps = ComponentPropsWithRef<typeof DialogPrimitive.Content> & {
  /** Required: the accessible name of the dialog. */
  title: string;
  description?: ReactNode;
};

export function DialogContent({ title, description, className, children, ...props }: DialogContentProps) {
  return (
    <DialogPrimitive.Portal>
      <DialogPrimitive.Overlay className="fixed inset-0 bg-fg/50" />
      <DialogPrimitive.Content className={cn('fixed top-1/2 left-1/2 w-full max-w-md -translate-1/2 rounded-md bg-bg p-6', className)} {...props}>
        <DialogPrimitive.Title>{title}</DialogPrimitive.Title>
        {description !== undefined && <DialogPrimitive.Description>{description}</DialogPrimitive.Description>}
        {children}
      </DialogPrimitive.Content>
    </DialogPrimitive.Portal>
  );
}
```

`export const Dialog = DialogPrimitive.Root`, `DialogTrigger`, and `DialogClose` are re-exported unchanged. A required `title` means no consumer can ship an unnamed dialog.

## Barrel Exports and `exports` Map

```ts
// src/index.ts
export { Button, buttonVariants, type ButtonProps } from './components/button';
export { Checkbox, type CheckboxProps } from './components/checkbox';
export { Dialog, DialogClose, DialogContent, DialogTrigger, type DialogContentProps } from './components/dialog';
export { cn } from './lib/cn';
```

`package.json` exposes exactly two entry points: `"."` for code and `"./theme.css"` for tokens. Consumers never deep-import `dist/` or `src/`. `tsup` emits ESM plus `.d.ts` with `react`, `react-dom`, and `react/jsx-runtime` external; `sideEffects` lists only CSS so bundlers tree-shake unused components. See [references/build-config.md](references/build-config.md) for `package.json`, `tsup.config.ts`, `tsconfig.json`, `vitest.config.ts`, and the Storybook config.

## Storybook

Storybook 8 with `@storybook/react-vite`, `@storybook/addon-a11y`, and `@storybook/addon-interactions`. `preview.tsx` imports `storybook.css`, adds a light/dark toolbar that sets `data-theme`, and sets `parameters.a11y.test = 'error'` so a violation fails the story.

```tsx
// src/components/button/Button.stories.tsx (excerpt)
import type { Meta, StoryObj } from '@storybook/react';
import { expect, fn, userEvent, within } from '@storybook/test';

import { Button } from './Button';

const meta = {
  title: 'Components/Button',
  component: Button,
  args: { children: 'Save changes', onClick: fn() },
  argTypes: { variant: { control: 'select', options: ['primary', 'outline', 'ghost', 'danger'] } },
} satisfies Meta<typeof Button>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Primary: Story = {};

export const Loading: Story = {
  args: { isLoading: true },
  play: async ({ args, canvasElement }) => {
    const button = within(canvasElement).getByRole('button', { name: 'Save changes' });
    await expect(button).toBeDisabled();
    await userEvent.click(button);
    await expect(args.onClick).not.toHaveBeenCalled();
  },
};
```

Rules: `satisfies Meta<typeof Component>`; one story per variant or state; `args` over `render` unless composition is needed; `fn()` for every callback; a `play` function for every interactive state.

## Testing

Every component folder has `Name.test.tsx` using `@testing-library/react`, `@testing-library/user-event`, and `vitest-axe`.

```tsx
// src/components/button/Button.test.tsx (excerpt)
describe('Button', () => {
  it('calls onClick when activated', async () => {
    const user = userEvent.setup();
    const onClick = vi.fn();
    render(<Button onClick={onClick}>Save</Button>);

    await user.click(screen.getByRole('button', { name: 'Save' }));

    expect(onClick).toHaveBeenCalledOnce();
  });

  it('has no accessibility violations', async () => {
    const { container } = render(<Button>Save</Button>);

    expect(await axe(container)).toHaveNoViolations();
  });
});
```

Test behavior and accessibility, not class names: roles, names, `toBeDisabled`, `toHaveAttribute('aria-busy', 'true')`, callbacks. A `toHaveClass` assertion is acceptable only to prove `className` merging.

## Visual Regression

Run `@storybook/test-runner` in CI to execute every `play` function and the a11y checks. Add Chromatic (or Playwright screenshots of `storybook-static`) once the library has consumers; review diffs on every pull request that touches `theme.css` or a component.

## Anti-Patterns

| Anti-Pattern                                     | Problem                                            | Correct Approach                                         |
| ------------------------------------------------ | -------------------------------------------------- | -------------------------------------------------------- |
| `forwardRef` wrappers                            | Unneeded in React 19; hides the props type         | Accept `ref` through `ComponentPropsWithRef<'button'>`   |
| Hardcoded `#hex` or `oklch()` in a component     | Bypasses theming; dark mode breaks                 | Use `--ui-*` tokens via Tailwind utilities               |
| `if (theme === 'dark')` in components            | Duplicates styling logic                           | `[data-theme='dark']` overrides variables                |
| Custom modal with `useEffect` focus code         | Focus trap, escape, and ARIA are easy to get wrong | Compose `@radix-ui/react-dialog`                         |
| `as` prop polymorphism                           | Loses prop types; leaks invalid attributes         | `asChild` with `@radix-ui/react-slot`                    |
| `className` ignored or applied first             | Consumers cannot override styles                   | `cn(variants(...), className)` with `className` last     |
| Default exports from components                  | Breaks barrel consistency and tree-shaking hints   | Named exports; barrel re-exports                         |
| Story without `args` or with hardcoded callbacks | Controls panel empty; interactions untracked       | `args` with `fn()` for callbacks                         |
| Deep imports `@acme/ui/dist/...` or `src/...`    | Couples apps to internal layout                    | Import from `@acme/ui`; tokens from `@acme/ui/theme.css` |
| Domain models in component props                 | UI package becomes app-specific                    | Accept primitives and `ReactNode`; map in the feature    |
| Skipping the axe test                            | Label and contrast regressions go unnoticed        | `expect(await axe(container)).toHaveNoViolations()`      |

## Common Workflows

### Adding a component

1. Create `src/components/<name>/` with `Name.tsx`, `Name.stories.tsx`, `Name.test.tsx`, `index.ts` from [references/component-template.md](references/component-template.md)
2. Compose the Radix primitive when one exists; define `cva` variants with `defaultVariants`
3. Export from `src/index.ts`
4. Write stories for every variant and state; run `pnpm storybook` and check the a11y panel
5. Write tests for behavior, accessible name, `className` merging, and axe; run `pnpm test:coverage`
6. Run `pnpm build` and confirm the component appears in `dist/index.d.ts`

### Adding a token

1. Add `--ui-<group>-<name>` to `:root` and, when it differs, to `[data-theme='dark']` in `theme.css`
2. Map it in `@theme inline` so a Tailwind utility exists
3. Replace any hardcoded value the token supersedes
4. Check both themes in Storybook via the toolbar

## Additional Resources

- [references/component-template.md](references/component-template.md) — complete `Button`: component with spinner and icon slots, `cn` helper and test, CSF3 story with `play` functions, Testing Library test, barrel entry, adaptation table
- [references/build-config.md](references/build-config.md) — `package.json` with `exports`, `sideEffects`, and `peerDependencies`; `tsup.config.ts`; `tsconfig.json`; `vitest.config.ts`; Storybook `main.ts` and `preview.tsx`; ESLint additions; consuming the package from an app
- For where `packages/ui` sits in the layer graph see the **react-architecture** skill; for scaffolding the package see the **react-create-project** skill
