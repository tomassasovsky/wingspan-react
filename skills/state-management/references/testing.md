# Testing State

Stack: `vitest`, `@testing-library/react`, `@testing-library/user-event`, `@testing-library/jest-dom`, `msw`. Network is always mocked with `msw`; never stub `fetch` or the repository by hand when a handler will do.

## Test Setup

```ts
// src/test/server.ts
import { setupServer } from 'msw/node';
import { handlers } from './handlers';

export const server = setupServer(...handlers);
```

```ts
// src/test/handlers.ts
import { http, HttpResponse } from 'msw';
import type { Todo } from '@acme/todo-repository';

export const todos: Todo[] = [
  { id: '1', title: 'Write tests', completed: false },
  { id: '2', title: 'Ship', completed: true },
];

export const handlers = [
  http.get('/api/todos', () => HttpResponse.json(todos)),
  http.post('/api/todos', async ({ request }) => {
    const body = (await request.json()) as { title: string };
    return HttpResponse.json({ id: '3', title: body.title, completed: false }, { status: 201 });
  }),
];
```

```ts
// src/test/setupTests.ts
import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterAll, afterEach, beforeAll } from 'vitest';
import { server } from './server';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  cleanup();
  server.resetHandlers();
});
afterAll(() => server.close());
```

```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setupTests.ts'],
    coverage: { provider: 'v8', thresholds: { lines: 100, functions: 100, branches: 100, statements: 100 } },
  },
});
```

## Query Wrapper Helper

A fresh `QueryClient` per test with retries off so failures surface immediately.

```tsx
// src/test/createQueryWrapper.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { createTodoRepository } from '@acme/todo-repository';
import { TodoRepositoryProvider } from '@/features/todos/hooks/useTodoRepository';

export function createQueryWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: Infinity },
      mutations: { retry: false },
    },
  });
  const repository = createTodoRepository({ baseUrl: '' });

  function Wrapper({ children }: { children: ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        <TodoRepositoryProvider repository={repository}>{children}</TodoRepositoryProvider>
      </QueryClientProvider>
    );
  }

  return { Wrapper, queryClient };
}
```

## Testing a Query Hook

```tsx
// src/features/todos/api/useTodosQuery.test.tsx
import { renderHook, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';
import { createQueryWrapper } from '@/test/createQueryWrapper';
import { server } from '@/test/server';
import { todos } from '@/test/handlers';
import { useTodosQuery } from './useTodosQuery';

describe('useTodosQuery', () => {
  it('returns todos from the API', async () => {
    const { Wrapper } = createQueryWrapper();
    const { result } = renderHook(() => useTodosQuery(), { wrapper: Wrapper });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toEqual(todos);
  });

  it('exposes the error when the API fails', async () => {
    server.use(http.get('/api/todos', () => HttpResponse.json({ message: 'boom' }, { status: 500 })));
    const { Wrapper } = createQueryWrapper();
    const { result } = renderHook(() => useTodosQuery(), { wrapper: Wrapper });

    await waitFor(() => expect(result.current.isError).toBe(true));
    expect(result.current.error?.message).toContain('500');
  });
});
```

## Testing a Mutation with Optimistic Update and Rollback

```tsx
// src/features/todos/api/useCreateTodoMutation.test.tsx
import { act, renderHook, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';
import { createQueryWrapper } from '@/test/createQueryWrapper';
import { server } from '@/test/server';
import { todos } from '@/test/handlers';
import { todoKeys } from './todoKeys';
import { useCreateTodoMutation } from './useCreateTodoMutation';
import { useTodosQuery } from './useTodosQuery';

function useTodosAndCreate() {
  return { query: useTodosQuery(), mutation: useCreateTodoMutation() };
}

describe('useCreateTodoMutation', () => {
  it('adds the todo optimistically and refetches on success', async () => {
    const { Wrapper, queryClient } = createQueryWrapper();
    const { result } = renderHook(useTodosAndCreate, { wrapper: Wrapper });
    await waitFor(() => expect(result.current.query.isSuccess).toBe(true));

    act(() => result.current.mutation.mutate({ title: 'New' }));

    await waitFor(() => expect(result.current.query.data).toHaveLength(3));
    expect(result.current.query.data?.[2]?.title).toBe('New');

    await waitFor(() => expect(result.current.mutation.isSuccess).toBe(true));
    await waitFor(() => expect(queryClient.isFetching({ queryKey: todoKeys.lists() })).toBe(0));
    expect(result.current.query.data?.[2]?.id).toBe('3');
  });

  it('rolls back when the API fails', async () => {
    server.use(http.post('/api/todos', () => HttpResponse.json({ message: 'nope' }, { status: 500 })));
    const { Wrapper } = createQueryWrapper();
    const { result } = renderHook(useTodosAndCreate, { wrapper: Wrapper });
    await waitFor(() => expect(result.current.query.isSuccess).toBe(true));

    act(() => result.current.mutation.mutate({ title: 'New' }));

    await waitFor(() => expect(result.current.mutation.isError).toBe(true));
    await waitFor(() => expect(result.current.query.data).toEqual(todos));
  });
});
```

Render the query and the mutation in one hook so both share a `QueryClient` and the test observes the cache the mutation edits.

## Testing a Store

See the `cartStore.test.ts` example in [zustand.md](zustand.md). Rules:

- Reset with `setState(getInitialState(), true)` in `beforeEach`
- Call actions through `getState()`; assert through `getState()` and exported selectors
- Never render a component to test store logic
- Test `persist` by reading `localStorage` after an action

## Testing a Reducer

Reducers are pure. Test them as a table.

```ts
// src/features/upload/hooks/uploadReducer.test.ts
import { describe, expect, it } from 'vitest';
import { initialUploadState, uploadReducer, type UploadAction, type UploadState } from './uploadReducer';

describe('uploadReducer', () => {
  it.each<[string, UploadState, UploadAction, UploadState]>([
    ['starts', initialUploadState, { type: 'started' }, { status: 'uploading', progress: 0 }],
    ['tracks progress', { status: 'uploading', progress: 0 }, { type: 'progressed', progress: 40 }, { status: 'uploading', progress: 40 }],
    ['ignores progress when idle', initialUploadState, { type: 'progressed', progress: 40 }, initialUploadState],
    ['succeeds', { status: 'uploading', progress: 99 }, { type: 'succeeded', url: '/f.png' }, { status: 'success', url: '/f.png' }],
    ['fails', { status: 'uploading', progress: 10 }, { type: 'failed', error: 'timeout' }, { status: 'failure', error: 'timeout' }],
    ['resets', { status: 'failure', error: 'x' }, { type: 'reset' }, initialUploadState],
  ])('%s', (_name, state, action, expected) => {
    expect(uploadReducer(state, action)).toEqual(expected);
  });

  it('returns the same reference when nothing changes', () => {
    const state: UploadState = { status: 'idle' };
    expect(uploadReducer(state, { type: 'progressed', progress: 1 })).toBe(state);
  });
});
```

## Testing a Component That Uses a Store

Seed the store, render, interact through the UI, assert on the DOM and the store.

```tsx
// src/features/cart/components/CartSummary.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it } from 'vitest';
import { useCartStore } from '../store/cartStore';
import { CartSummary } from './CartSummary';

describe('CartSummary', () => {
  beforeEach(() => {
    useCartStore.setState(useCartStore.getInitialState(), true);
    useCartStore.setState({
      items: [{ productId: 'p1', quantity: 2, unitPrice: 10 }],
      couponCode: 'SAVE10',
    });
  });

  it('renders derived count and subtotal', () => {
    render(<CartSummary />);
    expect(screen.getByText('2 items')).toBeInTheDocument();
    expect(screen.getByText('Subtotal: 20.00')).toBeInTheDocument();
  });

  it('clears the cart', async () => {
    const user = userEvent.setup();
    render(<CartSummary />);

    await user.click(screen.getByRole('button', { name: 'Clear cart' }));

    expect(screen.getByText('0 items')).toBeInTheDocument();
    expect(useCartStore.getState().items).toEqual([]);
  });

  it('removes the coupon', async () => {
    const user = userEvent.setup();
    render(<CartSummary />);

    await user.click(screen.getByRole('button', { name: 'Remove coupon' }));

    expect(useCartStore.getState().couponCode).toBeNull();
  });
});
```

## Testing a Component That Uses a Query

Use the shared `renderWithProviders` helper (which wraps `createQueryWrapper`) and drive data through `msw`. Assert on roles and text, never on `isLoading` flags.

```tsx
// src/features/todos/components/TodoList.test.tsx
import { screen } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';
import { renderWithProviders } from '@/test/renderWithProviders';
import { server } from '@/test/server';
import { TodoList } from './TodoList';

describe('TodoList', () => {
  it('renders todos', async () => {
    renderWithProviders(<TodoList />);
    expect(await screen.findByRole('listitem', { name: 'Write tests' })).toBeInTheDocument();
    expect(screen.getAllByRole('listitem')).toHaveLength(2);
  });

  it('renders an error state', async () => {
    server.use(http.get('/api/todos', () => HttpResponse.json({}, { status: 500 })));
    renderWithProviders(<TodoList />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Could not load todos');
  });
});
```

## Anti-Patterns in State Tests

| Anti-Pattern                                     | Problem                                    | Correct Approach                                    |
| ------------------------------------------------ | ------------------------------------------ | --------------------------------------------------- |
| `vi.mock('@tanstack/react-query')`               | Tests the mock, not the cache behavior     | Real `QueryClient` + `msw` handlers                 |
| `global.fetch = vi.fn()`                         | Bypasses parsing, headers, and error paths | `msw` handler per scenario                          |
| Sharing one `QueryClient` across tests           | Cache leaks between tests                  | `createQueryWrapper()` per test                     |
| Not resetting stores                             | Order-dependent tests                      | `setState(getInitialState(), true)` in `beforeEach` |
| Asserting `result.current.isLoading` transitions | Brittle timing assertions                  | `waitFor` on `isSuccess` or on rendered output      |
| `await new Promise((r) => setTimeout(r, 100))`   | Flaky                                      | `waitFor` / `findBy*`                               |
