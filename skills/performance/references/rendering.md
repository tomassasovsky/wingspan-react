# Rendering

## Why a Component Re-renders

A component renders again for exactly four reasons. Diagnose with the React DevTools Profiler setting "Record why each component rendered".

| Cause                      | Profiler says                        | Fix when it is a problem                                                          |
| -------------------------- | ------------------------------------ | --------------------------------------------------------------------------------- |
| Its own state changed      | "Hook 1 changed"                     | Expected; check the update is not redundant (`setState` to same value is skipped) |
| Its parent rendered        | "The parent component rendered"      | Colocate state lower, `children` pattern, or `memo` with measurement              |
| A context it reads changed | "Context changed"                    | Split the context; move values that change often into `zustand` with selectors    |
| Its props changed          | "Props changed: (onSelect, options)" | Stabilize the identity of the listed props                                        |

A render is not a DOM update. React diffs the output and commits only real changes. Re-renders matter only when the Profiler shows a commit longer than a few milliseconds or many commits per interaction.

## React Compiler

The compiler memoizes components, hooks, and values automatically. It requires code that follows the Rules of React; `eslint-plugin-react-hooks` v6 reports violations that make a component ineligible.

```ts
// vite.config.ts
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [
    react({
      babel: {
        plugins: [['babel-plugin-react-compiler', {}]],
      },
    }),
  ],
});
```

```ts
// next.config.ts
import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  reactCompiler: true,
};

export default nextConfig;
```

```js
// eslint.config.js (excerpt)
import reactHooks from 'eslint-plugin-react-hooks';

export default [
  reactHooks.configs.flat.recommended,
];
```

With the compiler enabled, delete existing `memo`, `useMemo`, and `useCallback` calls during refactors unless a comment records a measured reason to keep them. Verify a component compiled by checking for the "Memo" badge in React DevTools.

## Manual Memoization (No Compiler)

```tsx
import { memo, useCallback, useMemo, useState } from 'react';

import type { Order } from '@acme/orders-repository';

interface OrderRowProps {
  order: Order;
  onSelect: (id: string) => void;
}

const OrderRow = memo(function OrderRow({ order, onSelect }: OrderRowProps) {
  return (
    <tr>
      <td>{order.id}</td>
      <td>{order.customer}</td>
      <td>
        <button type="button" onClick={() => onSelect(order.id)}>Select</button>
      </td>
    </tr>
  );
});

export function OrderTable({ orders }: { orders: readonly Order[] }) {
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // Measured: sorting 5k orders costs 12 ms per render without useMemo.
  const sorted = useMemo(() => [...orders].sort((a, b) => a.customer.localeCompare(b.customer)), [orders]);

  // Stable identity so OrderRow's memo holds when selectedId changes.
  const handleSelect = useCallback((id: string) => setSelectedId(id), []);

  return (
    <table aria-label="Orders" data-selected={selectedId ?? undefined}>
      <tbody>
        {sorted.map((order) => (
          <OrderRow key={order.id} order={order} onSelect={handleSelect} />
        ))}
      </tbody>
    </table>
  );
}
```

Every manual memoization carries a comment with the measurement. A `memo` without a stable set of props is dead weight: one inline object prop breaks it.

## Context Splitting

A single context that holds both rarely-changing configuration and frequently-changing state forces every consumer to re-render on each change.

```tsx
// Before: one context, every consumer re-renders on every cart change.
interface AppContextValue {
  user: User;
  theme: Theme;
  cart: CartItem[];
  addToCart: (item: CartItem) => void;
}
```

```tsx
// After: separate contexts by update frequency; stable values and setters get their own context.
import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';

const SessionContext = createContext<{ user: User; theme: Theme } | null>(null);
const CartContext = createContext<readonly CartItem[] | null>(null);
const CartActionsContext = createContext<{ addToCart: (item: CartItem) => void } | null>(null);

export function AppProviders({ user, theme, children }: { user: User; theme: Theme; children: ReactNode }) {
  const [cart, setCart] = useState<readonly CartItem[]>([]);
  const session = useMemo(() => ({ user, theme }), [user, theme]);
  const actions = useMemo(() => ({ addToCart: (item: CartItem) => setCart((prev) => [...prev, item]) }), []);

  return (
    <SessionContext.Provider value={session}>
      <CartActionsContext.Provider value={actions}>
        <CartContext.Provider value={cart}>{children}</CartContext.Provider>
      </CartActionsContext.Provider>
    </SessionContext.Provider>
  );
}

export function useCartActions() {
  const value = useContext(CartActionsContext);
  if (!value) throw new Error('useCartActions must be used within AppProviders');
  return value;
}
```

A component that only adds to the cart reads `CartActionsContext` and never re-renders when the cart contents change. When state is shared across distant features and read with fine-grained selectors, use `zustand` instead of context: `useCartStore((state) => state.items.length)` re-renders only when the selected value changes.

## The `children` Pattern

State that lives in a wrapper does not re-render elements passed in as `children`, because those elements were created by the parent and their identity is unchanged.

```tsx
// Before: every mouse move re-renders <ExpensiveTree /> because it is rendered inside the stateful component.
export function TrackingArea() {
  const [position, setPosition] = useState({ x: 0, y: 0 });
  return (
    <div onMouseMove={(event) => setPosition({ x: event.clientX, y: event.clientY })}>
      <Coordinates position={position} />
      <ExpensiveTree />
    </div>
  );
}
```

```tsx
// After: the stateful wrapper receives ExpensiveTree as children; only Coordinates re-renders.
export function TrackingArea({ children }: { children: ReactNode }) {
  const [position, setPosition] = useState({ x: 0, y: 0 });
  return (
    <div onMouseMove={(event) => setPosition({ x: event.clientX, y: event.clientY })}>
      <Coordinates position={position} />
      {children}
    </div>
  );
}

// Usage
<TrackingArea>
  <ExpensiveTree />
</TrackingArea>
```

This is the same mechanism that keeps server components out of client bundles in Next: a client wrapper renders server-rendered `children` without owning them.

## State Colocation

| State                                   | Lives in                                    |
| --------------------------------------- | ------------------------------------------- |
| Input value, open/closed, hover         | The component that renders the control      |
| Form state                              | `react-hook-form` inside the form component |
| Filters, pagination, selected tab       | URL search params                           |
| Server data                             | `@tanstack/react-query` cache               |
| Cross-feature client state (cart, auth) | `zustand` store with selectors              |
| Theme, locale, session                  | Context at the root; values change rarely   |

Move state down until only the components that read it are inside the owner. A `useState` at the page level that only one leaf reads forces the whole page to re-render.

## Keys

| Rule                                             | Why                                                                                                   |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| Use a stable id from the data as `key`           | React reuses DOM and state by key; index keys attach state to the wrong item after reorder or removal |
| Never use `Math.random()` or a new id per render | Remounts every child on every render                                                                  |
| Change `key` deliberately to reset a subtree     | `<ProfileForm key={userId} />` resets form state when the user changes without an effect              |
| Keys are local to siblings                       | Two lists can reuse the same ids                                                                      |

## Testing Render Behavior

Tests assert observable behavior, not render counts. The one exception is a regression test for a measured optimization, where a render-counting probe documents the contract.

### Virtualized List

`jsdom` reports every element as 0 px tall, so the virtualizer renders nothing. Stub `getBoundingClientRect` for the test so the scroll container has a height.

```tsx
// src/features/orders/components/OrderList.test.tsx
import { screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { renderWithProviders } from '@/test/render';

import { OrderList } from './OrderList';

const orders = Array.from({ length: 10_000 }, (_, index) => ({
  id: String(index),
  customer: `Customer ${index}`,
  total: index,
}));

describe('OrderList', () => {
  beforeEach(() => {
    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
      width: 400, height: 480, top: 0, left: 0, right: 400, bottom: 480, x: 0, y: 0, toJSON: () => ({}),
    });
  });

  it('renders only the visible rows plus overscan when the list is long', () => {
    renderWithProviders(<OrderList orders={orders} height={480} rowHeight={48} />);

    const rows = screen.getAllByRole('listitem');

    expect(rows.length).toBeGreaterThan(0);
    expect(rows.length).toBeLessThan(40);
    expect(screen.getByText('Customer 0')).toBeInTheDocument();
    expect(screen.queryByText('Customer 9999')).not.toBeInTheDocument();
  });

  it('renders every row when the list fits in the viewport', () => {
    renderWithProviders(<OrderList orders={orders.slice(0, 3)} height={480} rowHeight={48} />);

    expect(screen.getAllByRole('listitem')).toHaveLength(3);
  });
});
```

`restoreMocks: true` in `vitest.config.ts` restores the spy after each test.

### Deferred Search

```tsx
// src/features/catalog/components/ProductSearch.test.tsx
import { screen, within } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { renderWithProviders } from '@/test/render';

import { ProductSearch } from './ProductSearch';

const products = [
  { id: '1', name: 'Desk Lamp' },
  { id: '2', name: 'Office Chair' },
];

describe('ProductSearch', () => {
  it('shows only matching products after the query settles', async () => {
    const { user } = renderWithProviders(<ProductSearch products={products} />);

    await user.type(screen.getByRole('searchbox', { name: /search products/i }), 'lamp');

    const results = await screen.findByRole('list', { name: /results/i });
    expect(await within(results).findByText('Desk Lamp')).toBeInTheDocument();
    expect(within(results).queryByText('Office Chair')).not.toBeInTheDocument();
  });

  it('shows empty message when nothing matches', async () => {
    const { user } = renderWithProviders(<ProductSearch products={products} />);

    await user.type(screen.getByRole('searchbox', { name: /search products/i }), 'zzz');

    expect(await screen.findByText(/no products match/i)).toBeInTheDocument();
  });
});
```

`findBy*` waits for the deferred render to commit; asserting synchronously after `user.type` races the deferred value.

### Transition

```tsx
// src/features/orders/components/OrderTabs.test.tsx
import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { renderWithProviders } from '@/test/render';

import { OrderTabs } from './OrderTabs';

describe('OrderTabs', () => {
  it('marks the archived tab selected and shows its panel when clicked', async () => {
    const { user } = renderWithProviders(<OrderTabs />);

    await user.click(screen.getByRole('tab', { name: /archived/i }));

    expect(screen.getByRole('tab', { name: /archived/i })).toHaveAttribute('aria-selected', 'true');
    expect(await screen.findByRole('heading', { name: /archived orders/i })).toBeInTheDocument();
    expect(screen.getByRole('tabpanel')).toHaveAttribute('aria-busy', 'false');
  });
});
```

```tsx
// src/features/orders/components/OrderTable.test.tsx (render-count regression for a measured memo)
import { screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { renderWithProviders } from '@/test/render';

import { OrderTable } from './OrderTable';

const onRowRender = vi.fn();
vi.mock('./OrderRow', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./OrderRow')>();
  return {
    OrderRow: (props: Parameters<typeof actual.OrderRow>[0]) => {
      onRowRender(props.order.id);
      return actual.OrderRow(props);
    },
  };
});

describe('OrderTable', () => {
  it('does not re-render rows when a row is selected', async () => {
    const orders = [
      { id: '1', customer: 'Dash', total: 10 },
      { id: '2', customer: 'Sparky', total: 20 },
    ];
    const { user } = renderWithProviders(<OrderTable orders={orders} />);
    onRowRender.mockClear();

    await user.click(screen.getAllByRole('button', { name: /select/i })[0]!);

    expect(onRowRender).not.toHaveBeenCalled();
  });
});
```

Render-count tests are rare and always link to the Profiler measurement that justified the optimization.
