# Patterns

## Context for Dependency Injection

Context holds instances that never change after app start. The hook throws when the provider is missing, so a misconfigured tree fails loudly in tests.

```tsx
// src/features/todos/hooks/useTodoRepository.tsx
import { createContext, use, type ReactNode } from 'react';
import type { TodoRepository } from '@acme/todo-repository';

const TodoRepositoryContext = createContext<TodoRepository | null>(null);

export function TodoRepositoryProvider({ repository, children }: { repository: TodoRepository; children: ReactNode }) {
  return <TodoRepositoryContext value={repository}>{children}</TodoRepositoryContext>;
}

export function useTodoRepository(): TodoRepository {
  const repository = use(TodoRepositoryContext);
  if (repository === null) {
    throw new Error('useTodoRepository must be used inside TodoRepositoryProvider');
  }
  return repository;
}
```

```tsx
// src/features/todos/hooks/useTodoRepository.test.tsx
import { renderHook } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { TodoRepository } from '@acme/todo-repository';
import { TodoRepositoryProvider, useTodoRepository } from './useTodoRepository';

describe('useTodoRepository', () => {
  it('returns the provided repository', () => {
    const repository = {} as TodoRepository;
    const { result } = renderHook(() => useTodoRepository(), {
      wrapper: ({ children }) => <TodoRepositoryProvider repository={repository}>{children}</TodoRepositoryProvider>,
    });
    expect(result.current).toBe(repository);
  });

  it('throws outside the provider', () => {
    expect(() => renderHook(() => useTodoRepository())).toThrow('useTodoRepository must be used inside TodoRepositoryProvider');
  });
});
```

| Belongs in context                  | Does not belong in context        |
| ----------------------------------- | --------------------------------- |
| Repository and API client instances | The current user (query)          |
| Analytics and logger instances      | Theme toggled by the user (store) |
| `QueryClient` (via its provider)    | Form values, filters, selections  |

## Async Flows

### Dependent Queries

Gate the second query on the first with `enabled`. Never chain fetches inside `queryFn`.

```ts
export function useUserProjectsQuery(userId: string | undefined) {
  const repository = useProjectRepository();
  return useQuery({
    queryKey: projectKeys.byUser(userId ?? ''),
    queryFn: ({ signal }) => repository.getProjectsForUser(userId as string, { signal }),
    enabled: userId !== undefined,
  });
}
```

### Sequential Mutations

Use `mutateAsync` inside a hook that owns the flow. Components call one function.

```ts
// src/features/checkout/hooks/useCheckout.ts
import { useMutation } from '@tanstack/react-query';
import { useNavigate } from 'react-router';
import { useCartStore } from '@/features/cart/store/cartStore';
import { useCreateOrderMutation } from '../api/useCreateOrderMutation';
import { usePayOrderMutation } from '../api/usePayOrderMutation';

export function useCheckout() {
  const createOrder = useCreateOrderMutation();
  const payOrder = usePayOrderMutation();
  const clearCart = useCartStore((state) => state.clear);
  const navigate = useNavigate();

  return useMutation({
    mutationFn: async (paymentMethodId: string) => {
      const order = await createOrder.mutateAsync();
      await payOrder.mutateAsync({ orderId: order.id, paymentMethodId });
      return order;
    },
    onSuccess: (order) => {
      clearCart();
      void navigate(`/orders/${order.id}`);
    },
  });
}
```

The component renders `checkout.isPending`, `checkout.error`, and calls `checkout.mutate(id)`. No `try`/`catch` in JSX.

### Debounced Search

Debounce the input, keep the debounced value in the query key, and let the cache handle deduplication.

```ts
export function useSearchQuery(term: string) {
  const debounced = useDebouncedValue(term, 300);
  const repository = useSearchRepository();
  return useQuery({
    queryKey: searchKeys.term(debounced),
    queryFn: ({ signal }) => repository.search(debounced, { signal }),
    enabled: debounced.length >= 2,
    placeholderData: keepPreviousData,
  });
}
```

```ts
// src/hooks/useDebouncedValue.ts
import { useEffect, useState } from 'react';

export function useDebouncedValue<T>(value: T, delayMs: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timeout = setTimeout(() => setDebounced(value), delayMs);
    return () => clearTimeout(timeout);
  }, [value, delayMs]);
  return debounced;
}
```

### Polling

```ts
useQuery({
  ...jobQueryOptions(repository, jobId),
  refetchInterval: (query) => (query.state.data?.status === 'running' ? 2000 : false),
});
```

## Derived State

| Source               | Derive with                                     |
| -------------------- | ----------------------------------------------- |
| Store state          | Exported selector: `selectSubtotal(state)`      |
| Query data           | `select` option on the query                    |
| Props or local state | Inline expression; `useMemo` only when measured |
| Several queries      | `useQueries` + `combine`                        |

```ts
// select transforms and memoizes per query; the component re-renders only when the result changes
export function useCompletedCountQuery() {
  const repository = useTodoRepository();
  return useQuery({
    ...todosQueryOptions(repository, {}),
    select: (todos) => todos.filter((todo) => todo.completed).length,
  });
}
```

```ts
const totals = useQueries({
  queries: accounts.map((account) => balanceQueryOptions(repository, account.id)),
  combine: (results) => ({
    total: results.reduce((sum, result) => sum + (result.data?.amount ?? 0), 0),
    isPending: results.some((result) => result.isPending),
  }),
});
```

Never write a `useEffect` that sets state from other state. If `b` is computed from `a`, compute `b` during render.

## State Machines with Discriminated Unions

Model any multi-step interaction as a union of states plus a union of events. Impossible combinations become type errors.

```ts
// src/features/auth/hooks/loginMachine.ts
export type LoginState =
  | { status: 'editing'; error: string | null }
  | { status: 'submitting' }
  | { status: 'mfa_required'; challengeId: string }
  | { status: 'verifying_mfa'; challengeId: string }
  | { status: 'authenticated' };

export type LoginEvent =
  | { type: 'submitted' }
  | { type: 'rejected'; error: string }
  | { type: 'mfa_requested'; challengeId: string }
  | { type: 'mfa_submitted' }
  | { type: 'succeeded' };

export const initialLoginState: LoginState = { status: 'editing', error: null };

export function loginReducer(state: LoginState, event: LoginEvent): LoginState {
  switch (state.status) {
    case 'editing':
      return event.type === 'submitted' ? { status: 'submitting' } : state;
    case 'submitting':
      switch (event.type) {
        case 'succeeded':
          return { status: 'authenticated' };
        case 'mfa_requested':
          return { status: 'mfa_required', challengeId: event.challengeId };
        case 'rejected':
          return { status: 'editing', error: event.error };
        default:
          return state;
      }
    case 'mfa_required':
      return event.type === 'mfa_submitted' ? { status: 'verifying_mfa', challengeId: state.challengeId } : state;
    case 'verifying_mfa':
      switch (event.type) {
        case 'succeeded':
          return { status: 'authenticated' };
        case 'rejected':
          return { status: 'editing', error: event.error };
        default:
          return state;
      }
    case 'authenticated':
      return state;
    default: {
      const exhaustive: never = state;
      return exhaustive;
    }
  }
}
```

Render with a `switch` on `state.status`. Each branch has access only to the fields that exist in that state.

```tsx
switch (state.status) {
  case 'editing':
    return <LoginForm error={state.error} onSubmit={submit} />;
  case 'submitting':
  case 'verifying_mfa':
    return <Spinner />;
  case 'mfa_required':
    return <MfaForm challengeId={state.challengeId} onSubmit={submitMfa} />;
  case 'authenticated':
    return <Navigate to="/" replace />;
}
```

Reach for `xstate` only when a machine needs nested states, parallel regions, or visualized transitions. A reducer covers the rest.

## `useSyncExternalStore`

Use it to subscribe to a store React does not own: browser APIs, third-party singletons, `window` events. Do not use it for data that belongs in a query or a `zustand` store; `zustand` already uses it internally.

| Source                         | Hook                   |
| ------------------------------ | ---------------------- |
| `matchMedia('(max-width: …)')` | `useMediaQuery`        |
| `navigator.onLine`             | `useOnlineStatus`      |
| `window.localStorage` key      | `useLocalStorageValue` |
| `document.visibilityState`     | `usePageVisible`       |

```ts
// src/hooks/useOnlineStatus.ts
import { useSyncExternalStore } from 'react';

function subscribe(onChange: () => void) {
  window.addEventListener('online', onChange);
  window.addEventListener('offline', onChange);
  return () => {
    window.removeEventListener('online', onChange);
    window.removeEventListener('offline', onChange);
  };
}

const getSnapshot = () => navigator.onLine;
const getServerSnapshot = () => true;

export function useOnlineStatus(): boolean {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
```

```ts
// src/hooks/useMediaQuery.ts
import { useCallback, useSyncExternalStore } from 'react';

export function useMediaQuery(query: string): boolean {
  const subscribe = useCallback(
    (onChange: () => void) => {
      const media = window.matchMedia(query);
      media.addEventListener('change', onChange);
      return () => media.removeEventListener('change', onChange);
    },
    [query],
  );
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia(query).matches,
    () => false,
  );
}
```

Rules:

- `getSnapshot` returns a primitive or a cached reference; a new object per call causes an infinite render loop
- Always provide `getServerSnapshot` in apps that server-render
- Define `subscribe` outside the component or memoize it; a new function each render resubscribes every render

```ts
// src/hooks/useOnlineStatus.test.ts
import { act, renderHook } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { useOnlineStatus } from './useOnlineStatus';

describe('useOnlineStatus', () => {
  it('reflects navigator.onLine and updates on events', () => {
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(true);
    const { result } = renderHook(() => useOnlineStatus());
    expect(result.current).toBe(true);

    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(false);
    act(() => window.dispatchEvent(new Event('offline')));
    expect(result.current).toBe(false);
  });
});
```
