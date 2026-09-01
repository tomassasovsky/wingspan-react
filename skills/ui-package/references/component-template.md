# Component Template: `Button`

A complete component folder. Copy it for every new component and replace the parts that differ.

```text
src/components/button/
├── Button.tsx
├── Button.stories.tsx
├── Button.test.tsx
└── index.ts
```

---

## `src/lib/cn.ts`

```ts
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/** Joins class names and resolves conflicting Tailwind utilities (last wins). */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
```

```ts
// src/lib/cn.test.ts
import { describe, expect, it } from 'vitest';

import { cn } from './cn';

describe('cn', () => {
  it('joins truthy values', () => {
    expect(cn('a', false, undefined, 'b')).toBe('a b');
  });

  it('lets the last conflicting utility win', () => {
    expect(cn('px-2 text-sm', 'px-4')).toBe('text-sm px-4');
  });
});
```

---

## `Button.tsx`

```tsx
import { Slot } from '@radix-ui/react-slot';
import { cva, type VariantProps } from 'class-variance-authority';
import type { ComponentPropsWithRef, ReactNode } from 'react';

import { cn } from '../../lib/cn';

export const buttonVariants = cva(
  [
    'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md font-medium',
    'transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring',
    'disabled:pointer-events-none disabled:opacity-50',
  ],
  {
    variants: {
      variant: {
        primary: 'bg-primary text-primary-fg hover:bg-primary/90',
        outline: 'border border-border bg-transparent text-fg hover:bg-muted',
        ghost: 'text-fg hover:bg-muted',
        danger: 'bg-danger text-danger-fg hover:bg-danger/90',
      },
      size: {
        sm: 'h-8 px-3 text-sm',
        md: 'h-10 px-4 text-sm',
        lg: 'h-12 px-6 text-base',
      },
    },
    defaultVariants: { variant: 'primary', size: 'md' },
  },
);

export type ButtonProps = ComponentPropsWithRef<'button'> &
  VariantProps<typeof buttonVariants> & {
    /** Render the single child element instead of a `<button>`, merging props and classes. */
    asChild?: boolean;
    /** Disables the button, announces `aria-busy`, and replaces the leading icon with a spinner. */
    isLoading?: boolean;
    leadingIcon?: ReactNode;
    trailingIcon?: ReactNode;
  };

function Spinner() {
  return (
    <span
      aria-hidden="true"
      data-testid="button-spinner"
      className="size-4 animate-spin rounded-full border-2 border-current border-t-transparent"
    />
  );
}

export function Button({
  className,
  variant,
  size,
  asChild = false,
  isLoading = false,
  disabled,
  type,
  leadingIcon,
  trailingIcon,
  children,
  ...props
}: ButtonProps) {
  const Component = asChild ? Slot : 'button';

  return (
    <Component
      className={cn(buttonVariants({ variant, size }), className)}
      disabled={disabled === true || isLoading}
      aria-busy={isLoading || undefined}
      type={asChild ? undefined : (type ?? 'button')}
      {...props}
    >
      {isLoading ? <Spinner /> : leadingIcon}
      {children}
      {trailingIcon}
    </Component>
  );
}
```

`data-testid` on the spinner is the one sanctioned use: the spinner is `aria-hidden` and has no role or name to query.

---

## `Button.stories.tsx`

```tsx
import type { Meta, StoryObj } from '@storybook/react';
import { expect, fn, userEvent, within } from '@storybook/test';

import { Button } from './Button';

const meta = {
  title: 'Components/Button',
  component: Button,
  tags: ['autodocs'],
  args: {
    children: 'Save changes',
    onClick: fn(),
  },
  argTypes: {
    variant: { control: 'select', options: ['primary', 'outline', 'ghost', 'danger'] },
    size: { control: 'inline-radio', options: ['sm', 'md', 'lg'] },
    asChild: { table: { disable: true } },
  },
} satisfies Meta<typeof Button>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Primary: Story = {};

export const Outline: Story = { args: { variant: 'outline' } };

export const Ghost: Story = { args: { variant: 'ghost' } };

export const Danger: Story = { args: { variant: 'danger', children: 'Delete' } };

export const Sizes: Story = {
  render: (args) => (
    <div className="flex items-center gap-3">
      <Button {...args} size="sm">
        Small
      </Button>
      <Button {...args} size="md">
        Medium
      </Button>
      <Button {...args} size="lg">
        Large
      </Button>
    </div>
  ),
};

export const WithIcons: Story = {
  args: {
    leadingIcon: <span aria-hidden="true">+</span>,
    trailingIcon: <span aria-hidden="true">&rarr;</span>,
  },
};

export const Disabled: Story = { args: { disabled: true } };

export const Loading: Story = {
  args: { isLoading: true },
  play: async ({ args, canvasElement }) => {
    const button = within(canvasElement).getByRole('button', { name: 'Save changes' });

    await expect(button).toBeDisabled();
    await expect(button).toHaveAttribute('aria-busy', 'true');
    await userEvent.click(button);
    await expect(args.onClick).not.toHaveBeenCalled();
  },
};

export const AsLink: Story = {
  args: { asChild: true, children: <a href="/docs">Read the docs</a> },
  play: async ({ canvasElement }) => {
    const link = within(canvasElement).getByRole('link', { name: 'Read the docs' });

    await expect(link).toHaveAttribute('href', '/docs');
  },
};

export const Clicks: Story = {
  play: async ({ args, canvasElement }) => {
    await userEvent.click(within(canvasElement).getByRole('button', { name: 'Save changes' }));

    await expect(args.onClick).toHaveBeenCalledOnce();
  },
};
```

---

## `Button.test.tsx`

```tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { axe } from 'vitest-axe';
import { createRef } from 'react';
import { describe, expect, it, vi } from 'vitest';

import { Button, buttonVariants } from './Button';

describe('Button', () => {
  it('renders a button with its accessible name and type="button" by default', () => {
    render(<Button>Save</Button>);

    const button = screen.getByRole('button', { name: 'Save' });
    expect(button).toHaveAttribute('type', 'button');
  });

  it('respects an explicit type', () => {
    render(<Button type="submit">Send</Button>);

    expect(screen.getByRole('button', { name: 'Send' })).toHaveAttribute('type', 'submit');
  });

  it('calls onClick when activated with the mouse and the keyboard', async () => {
    const user = userEvent.setup();
    const onClick = vi.fn();
    render(<Button onClick={onClick}>Save</Button>);

    await user.click(screen.getByRole('button', { name: 'Save' }));
    await user.keyboard('{Enter}');

    expect(onClick).toHaveBeenCalledTimes(2);
  });

  it('is disabled and does not fire onClick when disabled', async () => {
    const user = userEvent.setup();
    const onClick = vi.fn();
    render(
      <Button disabled onClick={onClick}>
        Save
      </Button>,
    );

    const button = screen.getByRole('button', { name: 'Save' });
    await user.click(button);

    expect(button).toBeDisabled();
    expect(onClick).not.toHaveBeenCalled();
  });

  it('announces busy, disables, and shows a spinner while loading', async () => {
    const user = userEvent.setup();
    const onClick = vi.fn();
    render(
      <Button isLoading leadingIcon={<span>icon</span>} onClick={onClick}>
        Save
      </Button>,
    );

    const button = screen.getByRole('button', { name: 'Save' });
    await user.click(button);

    expect(button).toBeDisabled();
    expect(button).toHaveAttribute('aria-busy', 'true');
    expect(screen.getByTestId('button-spinner')).toBeInTheDocument();
    expect(screen.queryByText('icon')).not.toBeInTheDocument();
    expect(onClick).not.toHaveBeenCalled();
  });

  it('renders leading and trailing icons', () => {
    render(
      <Button leadingIcon={<span>lead</span>} trailingIcon={<span>trail</span>}>
        Save
      </Button>,
    );

    expect(screen.getByText('lead')).toBeInTheDocument();
    expect(screen.getByText('trail')).toBeInTheDocument();
  });

  it('renders the child element when asChild is set', () => {
    render(
      <Button asChild variant="outline">
        <a href="/docs">Docs</a>
      </Button>,
    );

    const link = screen.getByRole('link', { name: 'Docs' });
    expect(link).toHaveAttribute('href', '/docs');
    expect(link).not.toHaveAttribute('type');
    expect(link).toHaveClass(buttonVariants({ variant: 'outline' }));
  });

  it('merges className after the variant classes', () => {
    render(<Button className="px-8">Save</Button>);

    const button = screen.getByRole('button', { name: 'Save' });
    expect(button).toHaveClass('px-8');
    expect(button).not.toHaveClass('px-4');
  });

  it('forwards ref to the underlying element', () => {
    const ref = createRef<HTMLButtonElement>();
    render(<Button ref={ref}>Save</Button>);

    expect(ref.current).toBe(screen.getByRole('button', { name: 'Save' }));
  });

  it.each(['primary', 'outline', 'ghost', 'danger'] as const)('has no a11y violations for the %s variant', async (variant) => {
    const { container } = render(<Button variant={variant}>Save</Button>);

    expect(await axe(container)).toHaveNoViolations();
  });
});
```

---

## `index.ts`

```ts
export { Button, buttonVariants, type ButtonProps } from './Button';
```

And in `src/index.ts`:

```ts
export { Button, buttonVariants, type ButtonProps } from './components/button';
```

---

## Adapting the template

| Component kind         | Replace                                                       | Keep                                                 |
| ---------------------- | ------------------------------------------------------------- | ---------------------------------------------------- |
| Native element wrapper | `'button'` in `ComponentPropsWithRef`; the `cva` variants     | `cn` merge, `ref` via props, story and test shape    |
| Radix composition      | `Slot`/`'button'` with `Primitive.Root` and parts             | Required accessibility props (`title`, `aria-label`) |
| Form control           | Add `id`, `name`, `value`, `onValueChange`; label association | `axe` test per state; `user-event` interactions      |
| Layout primitive       | Drop `isLoading`; variants become spacing and alignment       | `asChild`, `className` merge                         |
