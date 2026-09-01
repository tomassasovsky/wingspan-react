# Theming — Spacing

The 4px spacing scale, where each step is used, layout primitives that make spacing declarative, and density.

---

## Scale

| Token        | rem       | px  | Tailwind | Use                                        |
| ------------ | --------- | --- | -------- | ------------------------------------------ |
| `--space-0`  | `0`       | 0   | `p-0`    | Reset                                      |
| `--space-px` | `1px`     | 1   | `p-px`   | Hairline borders drawn with padding        |
| `--space-1`  | `0.25rem` | 4   | `p-1`    | Icon to label, badge padding               |
| `--space-2`  | `0.5rem`  | 8   | `p-2`    | Inline gaps, chip padding, tight lists     |
| `--space-3`  | `0.75rem` | 12  | `p-3`    | Input padding, compact card padding        |
| `--space-4`  | `1rem`    | 16  | `p-4`    | Default component padding, stack gap       |
| `--space-5`  | `1.25rem` | 20  | `p-5`    | Rare; between 4 and 6 when both look wrong |
| `--space-6`  | `1.5rem`  | 24  | `p-6`    | Card padding, form group gap               |
| `--space-8`  | `2rem`    | 32  | `p-8`    | Between content groups                     |
| `--space-10` | `2.5rem`  | 40  | `p-10`   | Dialog padding                             |
| `--space-12` | `3rem`    | 48  | `p-12`   | Section spacing                            |
| `--space-16` | `4rem`    | 64  | `p-16`   | Page sections                              |
| `--space-24` | `6rem`    | 96  | `p-24`   | Hero padding                               |

`rem` values scale with the root font size; interactive target sizes (`--size-target: 44px`) stay in `px` on purpose so zoom does not shrink hit areas below the WCAG minimum.

With Tailwind v4, `--spacing: 0.25rem` in `@theme` generates the whole scale; `p-4` is `calc(var(--spacing) * 4)`. Never use arbitrary values like `p-[13px]`.

---

## Rules

| Rule                                          | Detail                                                                                                     |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Gaps over margins                             | `gap` on the parent (`Stack`, `Inline`, grid) instead of `margin-bottom` on children; no last-child resets |
| Padding belongs to the container              | A card sets its own padding; children never add outer margin                                               |
| Logical properties only                       | `padding-inline`, `margin-block-start`; never `padding-left`                                               |
| Skip steps deliberately                       | Adjacent steps (4 then 5) rarely both appear in one component; jump 4 to 6 to 8                            |
| Optical alignment is a token too              | `--space-icon-offset: -0.125rem` when an icon needs to sit inside the text box                             |
| Negative space is `calc(-1 * var(--space-2))` | Never a raw negative pixel value                                                                           |

---

## Layout Primitives

`Stack` and `Inline` remove ad-hoc spacing from feature code. Feature components compose them and pass a `gap` step.

```tsx
// packages/ui/src/layout/Stack.tsx
import type { ComponentProps, CSSProperties } from 'react';

export type SpaceStep = 0 | 1 | 2 | 3 | 4 | 6 | 8 | 12 | 16;

type StackProps = ComponentProps<'div'> & {
  gap?: SpaceStep;
  align?: 'stretch' | 'start' | 'center' | 'end';
};

export function Stack({ gap = 4, align = 'stretch', style, className = '', ...rest }: StackProps) {
  const inline: CSSProperties = { ...style, '--stack-gap': `var(--space-${gap})`, alignItems: align } as CSSProperties;
  return <div className={`stack ${className}`.trim()} style={inline} {...rest} />;
}
```

```tsx
// packages/ui/src/layout/Inline.tsx
import type { ComponentProps, CSSProperties } from 'react';
import type { SpaceStep } from './Stack';

type InlineProps = ComponentProps<'div'> & {
  gap?: SpaceStep;
  align?: 'start' | 'center' | 'end' | 'baseline';
  justify?: 'start' | 'center' | 'end' | 'between';
  wrap?: boolean;
};

const justifyMap = { start: 'flex-start', center: 'center', end: 'flex-end', between: 'space-between' } as const;

export function Inline({ gap = 2, align = 'center', justify = 'start', wrap = true, style, className = '', ...rest }: InlineProps) {
  const inline: CSSProperties = {
    ...style,
    '--inline-gap': `var(--space-${gap})`,
    alignItems: align,
    justifyContent: justifyMap[justify],
    flexWrap: wrap ? 'wrap' : 'nowrap',
  } as CSSProperties;
  return <div className={`inline ${className}`.trim()} style={inline} {...rest} />;
}
```

```css
/* packages/ui/src/layout/layout.css */
.stack { display: flex; flex-direction: column; gap: var(--stack-gap); }
.inline { display: flex; gap: var(--inline-gap); }
```

The `as CSSProperties` cast is required because React's `CSSProperties` type does not include custom properties; keep the cast inside the primitive so feature code never repeats it.

```tsx
// packages/ui/src/layout/Stack.test.tsx
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Stack } from './Stack';

describe('Stack', () => {
  it('maps the gap step to a spacing token', () => {
    render(<Stack gap={6} data-testid="stack"><span>a</span></Stack>);
    expect(screen.getByTestId('stack').style.getPropertyValue('--stack-gap')).toBe('var(--space-6)');
  });

  it('defaults to a 16px gap and stretch alignment', () => {
    render(<Stack data-testid="stack"><span>a</span></Stack>);
    const stack = screen.getByTestId('stack');
    expect(stack.style.getPropertyValue('--stack-gap')).toBe('var(--space-4)');
    expect(stack).toHaveStyle({ alignItems: 'stretch' });
  });
});
```

`data-testid` is acceptable here: a layout primitive has no accessible role or name to query by.

Usage:

```tsx
<Stack gap={6}>
  <Text role="title-md">Billing</Text>
  <Stack gap={4}>
    <TextField label="Card number" autoComplete="cc-number" />
    <Inline gap={4}>
      <TextField label="Expiry" autoComplete="cc-exp" />
      <TextField label="CVC" autoComplete="cc-csc" />
    </Inline>
  </Stack>
  <Inline justify="end">
    <Button variant="secondary">Cancel</Button>
    <Button>Save card</Button>
  </Inline>
</Stack>
```

With Tailwind, `Stack` and `Inline` still exist and emit `flex flex-col gap-6` classes from the same `gap` prop; the prop keeps the scale enforced at the type level.

---

## Density

Dense data views (tables, admin panels) shrink padding, not the scale. Density is a data attribute on a container that reassigns component tokens; the scale itself never changes.

```css
[data-density='compact'] {
  --table-cell-padding-block: var(--space-1);
  --table-cell-padding-inline: var(--space-2);
  --input-padding-block: var(--space-1);
}
[data-density='comfortable'] {
  --table-cell-padding-block: var(--space-3);
  --table-cell-padding-inline: var(--space-4);
  --input-padding-block: var(--space-3);
}
```

Compact density never reduces an interactive target below `--size-target` (44px); it reduces whitespace around content, not the hit area of controls.
