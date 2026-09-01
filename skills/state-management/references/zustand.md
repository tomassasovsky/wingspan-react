# Zustand

`zustand` holds client state that distant components share: cart, session, theme, feature flags, UI preferences. It never holds server data.

## Slices Pattern with Middleware

Split a store into slices by sub-concern. Type each slice with `StateCreator` and list every middleware the combined store applies.

```ts
// src/features/cart/store/cartStore.ts
import { create, type StateCreator } from 'zustand';
import { createJSONStorage, devtools, persist } from 'zustand/middleware';

export interface CartItem {
  productId: string;
  quantity: number;
  unitPrice: number;
}

interface ItemsSlice {
  items: CartItem[];
  addItem: (item: CartItem) => void;
  removeItem: (productId: string) => void;
  clear: () => void;
}

interface CouponSlice {
  couponCode: string | null;
  applyCoupon: (code: string) => void;
  removeCoupon: () => void;
}

export type CartStore = ItemsSlice & CouponSlice;

type CartSlice<T> = StateCreator<
  CartStore,
  [['zustand/devtools', never], ['zustand/persist', unknown]],
  [],
  T
>;

const createItemsSlice: CartSlice<ItemsSlice> = (set) => ({
  items: [],
  addItem: (item) =>
    set(
      (state) => {
        const exists = state.items.some((i) => i.productId === item.productId);
        return {
          items: exists
            ? state.items.map((i) =>
                i.productId === item.productId ? { ...i, quantity: i.quantity + item.quantity } : i,
              )
            : [...state.items, item],
        };
      },
      false,
      'cart/addItem',
    ),
  removeItem: (productId) =>
    set((state) => ({ items: state.items.filter((i) => i.productId !== productId) }), false, 'cart/removeItem'),
  clear: () => set({ items: [] }, false, 'cart/clear'),
});

const createCouponSlice: CartSlice<CouponSlice> = (set) => ({
  couponCode: null,
  applyCoupon: (code) => set({ couponCode: code }, false, 'cart/applyCoupon'),
  removeCoupon: () => set({ couponCode: null }, false, 'cart/removeCoupon'),
});

export const useCartStore = create<CartStore>()(
  devtools(
    persist(
      (...args) => ({ ...createItemsSlice(...args), ...createCouponSlice(...args) }),
      {
        name: 'cart',
        storage: createJSONStorage(() => localStorage),
        partialize: (state) => ({ items: state.items, couponCode: state.couponCode }),
        version: 1,
      },
    ),
    { name: 'CartStore', enabled: import.meta.env.DEV },
  ),
);
```

The third argument to `set` is the action name shown in Redux DevTools. Use `<store>/<action>`.

## Middleware

| Middleware              | Import                     | Use for                                                |
| ----------------------- | -------------------------- | ------------------------------------------------------ |
| `persist`               | `zustand/middleware`       | Survive reloads; always `partialize` to data-only keys |
| `devtools`              | `zustand/middleware`       | Redux DevTools; enable in development only             |
| `subscribeWithSelector` | `zustand/middleware`       | `store.subscribe(selector, listener)` outside React    |
| `immer`                 | `zustand/middleware/immer` | Deep nested updates; still no mutation outside `set`   |

Order middleware outermost-first as `devtools(persist(immer(...)))`. `devtools` must wrap everything so it records every change.

### Persist: Migrations and Hydration

```ts
persist(creator, {
  name: 'cart',
  version: 2,
  migrate: (persisted, version) => {
    const state = persisted as Partial<CartStore>;
    if (version < 2) {
      return { ...state, couponCode: null };
    }
    return state;
  },
  onRehydrateStorage: () => (state, error) => {
    if (error) console.error('cart rehydration failed', error);
  },
});
```

Bump `version` whenever the persisted shape changes. Check `useCartStore.persist.hasHydrated()` before rendering persisted values on the server-rendered path to avoid hydration mismatches.

## Selectors

| Pattern                                                 | Re-renders when                      |
| ------------------------------------------------------- | ------------------------------------ |
| `useCartStore((s) => s.items)`                          | `items` reference changes            |
| `useCartStore(selectItemCount)`                         | Computed number changes              |
| `useCartStore(useShallow((s) => ({ a: s.a, b: s.b })))` | `a` or `b` changes (shallow compare) |
| `useCartStore()`                                        | Anything changes (never do this)     |

Selectors that return new objects or arrays on every call need `useShallow`; otherwise the component re-renders on every store update.

Define named selectors next to the store and export them; components never write inline selector logic beyond a single property read.

## Reading and Subscribing Outside React

```ts
// In a non-React module such as an API client interceptor
const { couponCode } = useCartStore.getState();

// React to changes without a component
const unsubscribe = useCartStore.subscribe((state, previous) => {
  if (state.items.length !== previous.items.length) analytics.track('cart_changed');
});
```

Call store actions from event handlers and effects only. Never call `setState` from render.

## Store Factories for Per-Instance State

A global hook is wrong when the same store is needed per widget instance (two independent wizards on one page). Create the store in a provider and expose it through context.

```tsx
// src/features/wizard/store/wizardStore.tsx
import { createContext, use, useState, type ReactNode } from 'react';
import { createStore, useStore, type StoreApi } from 'zustand';

interface WizardStore {
  step: number;
  next: () => void;
  back: () => void;
}

function createWizardStore(initialStep: number) {
  return createStore<WizardStore>()((set) => ({
    step: initialStep,
    next: () => set((state) => ({ step: state.step + 1 })),
    back: () => set((state) => ({ step: Math.max(0, state.step - 1) })),
  }));
}

const WizardStoreContext = createContext<StoreApi<WizardStore> | null>(null);

export function WizardStoreProvider({ initialStep = 0, children }: { initialStep?: number; children: ReactNode }) {
  const [store] = useState(() => createWizardStore(initialStep));
  return <WizardStoreContext value={store}>{children}</WizardStoreContext>;
}

export function useWizardStore<T>(selector: (state: WizardStore) => T): T {
  const store = use(WizardStoreContext);
  if (store === null) throw new Error('useWizardStore must be used inside WizardStoreProvider');
  return useStore(store, selector);
}
```

This is also the correct shape for Next.js App Router, where a module-level store would be shared across requests on the server.

## Resetting State Between Tests

Stores are module singletons. Reset them in `beforeEach` or state leaks between tests.

```ts
// src/features/cart/store/cartStore.test.ts
import { beforeEach, describe, expect, it } from 'vitest';
import { selectItemCount, selectSubtotal, useCartStore } from './cartStore';

const item = { productId: 'p1', quantity: 2, unitPrice: 10 };

describe('cartStore', () => {
  beforeEach(() => {
    useCartStore.setState(useCartStore.getInitialState(), true);
    useCartStore.persist.clearStorage();
  });

  it('adds a new item', () => {
    useCartStore.getState().addItem(item);
    expect(useCartStore.getState().items).toEqual([item]);
  });

  it('merges quantity for an existing product', () => {
    useCartStore.getState().addItem(item);
    useCartStore.getState().addItem({ ...item, quantity: 3 });
    expect(useCartStore.getState().items).toEqual([{ ...item, quantity: 5 }]);
  });

  it('removes an item', () => {
    useCartStore.getState().addItem(item);
    useCartStore.getState().removeItem('p1');
    expect(useCartStore.getState().items).toEqual([]);
  });

  it('derives count and subtotal', () => {
    useCartStore.getState().addItem(item);
    expect(selectItemCount(useCartStore.getState())).toBe(2);
    expect(selectSubtotal(useCartStore.getState())).toBe(20);
  });

  it('does not persist actions', () => {
    useCartStore.getState().addItem(item);
    const persisted = JSON.parse(localStorage.getItem('cart') ?? '{}') as { state: Record<string, unknown> };
    expect(Object.keys(persisted.state)).toEqual(['items', 'couponCode']);
  });
});
```

`setState(state, true)` replaces the whole state instead of merging. `getInitialState()` returns the state the creator produced, including actions, so nothing is lost.

To reset every store automatically, register each store in a `src/test/resetStores.ts` module and call it from `setupTests.ts`:

```ts
// src/test/setupTests.ts
import '@testing-library/jest-dom/vitest';
import { afterEach } from 'vitest';
import { cleanup } from '@testing-library/react';
import { useCartStore } from '@/features/cart/store/cartStore';

afterEach(() => {
  cleanup();
  useCartStore.setState(useCartStore.getInitialState(), true);
});
```

## No Server Data in Stores

A store that caches API responses reimplements `@tanstack/react-query` badly: no staleness, no deduplication, no cancellation, no invalidation, no devtools for requests.

```ts
// Wrong: server data in a store
interface TodosStore {
  todos: Todo[];
  loading: boolean;
  fetchTodos: () => Promise<void>;
}
```

```ts
// Right: server data in a query, client-only state in a store
export function useTodosQuery(filters: TodoFilters) { /* @tanstack/react-query */ }

interface TodoUiStore {
  selectedIds: Set<string>;
  toggleSelected: (id: string) => void;
}
```

| Data                                | Home                  |
| ----------------------------------- | --------------------- |
| Todo list from the API              | `useTodosQuery`       |
| Which todos the user multi-selected | `useTodoUiStore`      |
| Current filter                      | URL search params     |
| Todo currently being edited inline  | `useState` in the row |

The only exception is a session token held in memory after login, and only when it cannot live in an `httpOnly` cookie.
