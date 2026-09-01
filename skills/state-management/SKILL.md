---
name: react-state-management
description: Best practices for state management in React applications using local state, URL search params, @tanstack/react-query for server state, and zustand for cross-cutting client state. Use when writing, modifying, or reviewing query hooks, mutations, stores, reducers, selectors, or any code that uses @tanstack/react-query, zustand, useState, useReducer, or React context.
allowed-tools: Read Glob Grep
---

# State Management

Where state lives in a React application and how to model it: local state in components, URL state in the router, server state in `@tanstack/react-query`, and cross-cutting client state in `zustand`.

---

## Core Standards

Apply these standards to ALL state management work:

- **Server state lives in `@tanstack/react-query` only** — never copy fetched data into `zustand` or `useState`
- **Query keys come from a key factory** — never inline array literals in `useQuery` or `invalidateQueries`
- **Business logic lives in hooks, stores, and reducers** — never in JSX or inline event handlers
- **One store per concern** — never one global store for the whole app
- **Read stores through selectors** — never `useCartStore()` without a selector; it re-renders on every change
- **Derive, don't duplicate** — compute values from source state; never store a value that can be computed
- **Immutable updates only** — spread, `map`, and `filter` into new objects; never mutate state in place
- **Discriminated unions for multi-state values** — never parallel booleans such as `isLoading` plus `isError`
- **Context is for dependency injection** — never for frequently-changing state
- **Colocate state with its owner** — lift state only to the lowest common ancestor that needs it
- **Every hook, store, and reducer ships with a test** — `vitest` + `@testing-library/react` + `msw`

---

## Where State Lives

Work down this table and stop at the first row that matches.

| State                                      | Lives in                     | Tool                                   |
| ------------------------------------------ | ---------------------------- | -------------------------------------- |
| Input value, toggle, open/closed, hover    | The component                | `useState`; `useReducer` for 3+ fields |
| Filters, pagination, sort, active tab, ids | The URL                      | Router search params                   |
| Anything fetched from an API               | The query cache              | `@tanstack/react-query`                |
| Cart, session, theme, feature flags        | A store shared across routes | `zustand` with slices and selectors    |
| Repository, API client, analytics instance | React context                | `createContext` + typed provider hook  |

URL state examples live in the `react-routing` skill. Never put the same fact in two rows.

---

## Naming Conventions

| Thing                   | Pattern                       | Example                             |
| ----------------------- | ----------------------------- | ----------------------------------- |
| Query hook              | `use<Resource>Query`          | `useTodosQuery`, `useTodoQuery`     |
| Mutation hook           | `use<Verb><Resource>Mutation` | `useCreateTodoMutation`             |
| Query options factory   | `<resource>QueryOptions`      | `todosQueryOptions(filters)`        |
| Query key factory       | `<resource>Keys`              | `todoKeys.list(filters)`            |
| Store hook              | `use<Concern>Store`           | `useCartStore`                      |
| Store file              | `<concern>Store.ts`           | `store/cartStore.ts`                |
| Store action            | Imperative verb               | `addItem`, `removeItem`, `clear`    |
| Selector                | `select<Value>`               | `selectItemCount`, `selectSubtotal` |
| Reducer action `type`   | Past-tense event              | `'started'`, `'upload_failed'`      |
| Repository context hook | `use<Resource>Repository`     | `useTodoRepository`                 |

---

## Server State: `@tanstack/react-query`

### Query Key Factory

```ts
// src/features/todos/api/todoKeys.ts
import type { TodoFilters } from '@acme/todo-repository';

export const todoKeys = {
  all: ['todos'] as const,
  lists: () => [...todoKeys.all, 'list'] as const,
  list: (filters: TodoFilters) => [...todoKeys.lists(), filters] as const,
  details: () => [...todoKeys.all, 'detail'] as const,
  detail: (id: string) => [...todoKeys.details(), id] as const,
};
```

### Query Hook

```ts
// src/features/todos/api/useTodosQuery.ts
import { queryOptions, useQuery } from '@tanstack/react-query';
import type { TodoFilters, TodoRepository } from '@acme/todo-repository';
import { useTodoRepository } from '../hooks/useTodoRepository';
import { todoKeys } from './todoKeys';

export function todosQueryOptions(repository: TodoRepository, filters: TodoFilters) {
  return queryOptions({
    queryKey: todoKeys.list(filters),
    queryFn: ({ signal }) => repository.getTodos(filters, { signal }),
  });
}

export function useTodosQuery(filters: TodoFilters = {}) {
  const repository = useTodoRepository();
  return useQuery(todosQueryOptions(repository, filters));
}
```

### Mutation Hook with Optimistic Update and Invalidation

```ts
// src/features/todos/api/useCreateTodoMutation.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import type { CreateTodoInput, Todo } from '@acme/todo-repository';
import { useTodoRepository } from '../hooks/useTodoRepository';
import { todoKeys } from './todoKeys';

export function useCreateTodoMutation() {
  const repository = useTodoRepository();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (input: CreateTodoInput) => repository.createTodo(input),
    onMutate: async (input) => {
      await queryClient.cancelQueries({ queryKey: todoKeys.lists() });
      const previous = queryClient.getQueriesData<Todo[]>({ queryKey: todoKeys.lists() });
      const optimistic: Todo = { id: `optimistic-${crypto.randomUUID()}`, title: input.title, completed: false };
      queryClient.setQueriesData<Todo[]>({ queryKey: todoKeys.lists() }, (old) =>
        old ? [...old, optimistic] : [optimistic],
      );
      return { previous };
    },
    onError: (_error, _input, context) => {
      for (const [key, data] of context?.previous ?? []) {
        queryClient.setQueryData(key, data);
      }
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: todoKeys.lists() }),
  });
}
```

See [references/tanstack-query.md](references/tanstack-query.md) for `QueryClient` defaults, suspense, prefetching, pagination and infinite queries, error handling, and Next.js hydration.

---

## Client State: `zustand`

```ts
// src/features/cart/store/cartStore.ts
import { create, type StateCreator } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';

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

type CartSlice<T> = StateCreator<CartStore, [['zustand/persist', unknown]], [], T>;

const createItemsSlice: CartSlice<ItemsSlice> = (set) => ({
  items: [],
  addItem: (item) =>
    set((state) => {
      const exists = state.items.some((i) => i.productId === item.productId);
      return {
        items: exists
          ? state.items.map((i) =>
              i.productId === item.productId ? { ...i, quantity: i.quantity + item.quantity } : i,
            )
          : [...state.items, item],
      };
    }),
  removeItem: (productId) =>
    set((state) => ({ items: state.items.filter((i) => i.productId !== productId) })),
  clear: () => set({ items: [] }),
});

const createCouponSlice: CartSlice<CouponSlice> = (set) => ({
  couponCode: null,
  applyCoupon: (code) => set({ couponCode: code }),
  removeCoupon: () => set({ couponCode: null }),
});

export const useCartStore = create<CartStore>()(
  persist(
    (...args) => ({ ...createItemsSlice(...args), ...createCouponSlice(...args) }),
    {
      name: 'cart',
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ items: state.items, couponCode: state.couponCode }),
    },
  ),
);

// Selectors derive values; nothing derived is stored.
export const selectItemCount = (state: CartStore) =>
  state.items.reduce((sum, item) => sum + item.quantity, 0);
export const selectSubtotal = (state: CartStore) =>
  state.items.reduce((sum, item) => sum + item.quantity * item.unitPrice, 0);
```

```tsx
// src/features/cart/components/CartSummary.tsx
import { useShallow } from 'zustand/react/shallow';
import { selectItemCount, selectSubtotal, useCartStore } from '../store/cartStore';

export function CartSummary() {
  const count = useCartStore(selectItemCount);
  const subtotal = useCartStore(selectSubtotal);
  const { clear, removeCoupon } = useCartStore(
    useShallow((state) => ({ clear: state.clear, removeCoupon: state.removeCoupon })),
  );
  return (
    <section aria-label="Cart summary">
      <p>{count} items</p>
      <p>Subtotal: {subtotal.toFixed(2)}</p>
      <button type="button" onClick={removeCoupon}>Remove coupon</button>
      <button type="button" onClick={clear}>Clear cart</button>
    </section>
  );
}
```

`useShallow` compares the selected object field by field, so the component re-renders only when `clear` or `removeCoupon` changes (never, since actions are stable).

See [references/zustand.md](references/zustand.md) for the slices pattern with `devtools`, middleware, store factories, resetting stores between tests, and why server data never goes in a store.

---

## Local State: `useReducer` with a Discriminated Union

```ts
// src/features/upload/hooks/uploadReducer.ts
export type UploadState =
  | { status: 'idle' }
  | { status: 'uploading'; progress: number }
  | { status: 'success'; url: string }
  | { status: 'failure'; error: string };

export type UploadAction =
  | { type: 'started' }
  | { type: 'progressed'; progress: number }
  | { type: 'succeeded'; url: string }
  | { type: 'failed'; error: string }
  | { type: 'reset' };

export const initialUploadState: UploadState = { status: 'idle' };

export function uploadReducer(state: UploadState, action: UploadAction): UploadState {
  switch (action.type) {
    case 'started':
      return { status: 'uploading', progress: 0 };
    case 'progressed':
      return state.status === 'uploading' ? { status: 'uploading', progress: action.progress } : state;
    case 'succeeded':
      return { status: 'success', url: action.url };
    case 'failed':
      return { status: 'failure', error: action.error };
    case 'reset':
      return initialUploadState;
    default: {
      const exhaustive: never = action;
      return exhaustive;
    }
  }
}
```

Consume with `useReducer(uploadReducer, initialUploadState)`. The `never` assignment fails to compile when a new action is added without a matching case.

---

## Context for Dependency Injection

Context carries stable instances created once at the app root: repositories, API clients, analytics. Expose each through a `use<Resource>` hook that throws outside its provider. Anything that changes per interaction belongs in a query, a store, or local state.

See [references/patterns.md](references/patterns.md) for the `useTodoRepository` provider and hook.

---

## Anti-Patterns

| Anti-Pattern                                      | Problem                                  | Correct Approach                                       |
| ------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------ |
| `useEffect` + `useState` to fetch data            | No caching, races, duplicate requests    | `useQuery` with a key factory                          |
| Copying query data into a `zustand` store         | Two sources of truth that drift          | Read from the query; derive in a selector or `useMemo` |
| `const store = useCartStore()`                    | Re-renders on every store change         | `useCartStore(selectItemCount)` or `useShallow`        |
| Storing `total` next to `items`                   | Stale derived value                      | `selectSubtotal(state)` computed from `items`          |
| `state.items.push(item)` inside `set`             | Mutation bypasses change detection       | `set((s) => ({ items: [...s.items, item] }))`          |
| `isLoading`, `isError`, `data` as separate fields | Impossible states are representable      | `{ status: 'loading' } \| { status: 'error'; error }`  |
| Filters in `useState`                             | Not shareable, lost on refresh           | Router search params                                   |
| One `useAppStore` with every concern              | Every consumer couples to everything     | One store per concern: `useCartStore`, `useThemeStore` |
| Context holding frequently-changing values        | Every consumer re-renders on each change | `zustand` store with selectors                         |
| `queryKey: ['todos', id]` inline                  | Typos and inconsistent invalidation      | `todoKeys.detail(id)`                                  |
| Business logic in `onClick`                       | Untestable without rendering             | Move into a hook, store action, or reducer             |

---

## References

- [references/tanstack-query.md](references/tanstack-query.md) — query key factories, `QueryClient` defaults, `useSuspenseQuery`, prefetching, pagination and infinite queries, error handling, Next.js hydration
- [references/zustand.md](references/zustand.md) — slices with middleware, `devtools`/`persist`/`immer`, store factories, reading stores outside React, resetting state between tests, no server data in stores
- [references/testing.md](references/testing.md) — `msw` setup, testing query and mutation hooks with `renderHook` + wrapper, testing stores, reducers, and components that use them
- [references/patterns.md](references/patterns.md) — async flows, dependent queries, derived state, state machines with discriminated unions, when to use `useSyncExternalStore`
