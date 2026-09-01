# Layer Testing

Each layer is tested in isolation against a fake of the layer directly beneath it. Code under test is from [data-flow.md](data-flow.md).

| Layer          | Subject             | Fake beneath it     | Tool                                         |
| -------------- | ------------------- | ------------------- | -------------------------------------------- |
| Data           | API client          | The network         | `msw` (`setupServer` from `msw/node`)        |
| Domain         | Repository          | API client          | `vi.fn()` typed against `TodosApiClient`     |
| Business logic | Query/mutation hook | Repository          | `renderHook` + `QueryClientProvider` wrapper |
| Presentation   | View                | Nothing; props only | `@testing-library/react` + `user-event`      |
| Presentation   | Page                | Repository          | `renderWithProviders` with a fake repository |

---

## Data layer: API client with `msw`

```ts
// packages/todos-api-client/src/todos-api-client.test.ts
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import { TodosApiError } from './errors';
import { createTodosApiClient } from './todos-api-client';

const baseUrl = 'https://api.test';
const server = setupServer();

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
});
afterEach(() => {
  server.resetHandlers();
});
afterAll(() => {
  server.close();
});

const todoJson = { id: 1, title: 'Buy milk', completed: false, created_at: '2025-01-01T00:00:00Z' };

describe('createTodosApiClient', () => {
  const client = createTodosApiClient({ baseUrl });

  describe('getTodos', () => {
    it('returns parsed DTOs when the response is 200', async () => {
      server.use(http.get(`${baseUrl}/todos`, () => HttpResponse.json([todoJson])));

      await expect(client.getTodos()).resolves.toEqual([todoJson]);
    });

    it('throws TodosApiError with the status when the response is not ok', async () => {
      server.use(http.get(`${baseUrl}/todos`, () => HttpResponse.text('boom', { status: 500 })));

      await expect(client.getTodos()).rejects.toMatchObject({
        name: 'TodosApiError',
        status: 500,
        body: 'boom',
      });
    });

    it('throws when the payload does not match the schema', async () => {
      server.use(http.get(`${baseUrl}/todos`, () => HttpResponse.json([{ id: 'nope' }])));

      await expect(client.getTodos()).rejects.toThrow();
    });
  });

  describe('updateTodo', () => {
    it('sends a PATCH with a JSON body and returns the updated DTO', async () => {
      let receivedBody: unknown;
      server.use(
        http.patch(`${baseUrl}/todos/1`, async ({ request }) => {
          receivedBody = await request.json();
          return HttpResponse.json({ ...todoJson, completed: true });
        }),
      );

      const result = await client.updateTodo(1, { completed: true });

      expect(receivedBody).toEqual({ completed: true });
      expect(result.completed).toBe(true);
    });

    it('surfaces 404 as TodosApiError', async () => {
      server.use(http.patch(`${baseUrl}/todos/1`, () => HttpResponse.text('', { status: 404 })));

      await expect(client.updateTodo(1, { completed: true })).rejects.toBeInstanceOf(TodosApiError);
    });
  });
});
```

`onUnhandledRequest: 'error'` turns a wrong URL into a failing test instead of a hanging fetch.

---

## Domain layer: repository with a fake client

```ts
// packages/todos-repository/src/todos-repository.test.ts
import { TodosApiError, type TodoDto, type TodosApiClient } from '@acme/todos-api-client';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { TodoNotFoundError } from './errors';
import { toTodoId } from './models/todo';
import { createTodosRepository, type TodosRepository } from './todos-repository';

function createFakeApiClient(): { [K in keyof TodosApiClient]: ReturnType<typeof vi.fn<TodosApiClient[K]>> } {
  return {
    getTodos: vi.fn<TodosApiClient['getTodos']>(),
    getTodo: vi.fn<TodosApiClient['getTodo']>(),
    updateTodo: vi.fn<TodosApiClient['updateTodo']>(),
  };
}

const dto: TodoDto = { id: 1, title: '  Buy milk ', completed: false, created_at: '2025-01-01T00:00:00Z' };

describe('createTodosRepository', () => {
  let apiClient: ReturnType<typeof createFakeApiClient>;
  let subject: TodosRepository;

  beforeEach(() => {
    apiClient = createFakeApiClient();
    subject = createTodosRepository({ apiClient });
  });

  describe('getTodos', () => {
    it('maps every DTO to a domain model', async () => {
      apiClient.getTodos.mockResolvedValue([dto]);

      await expect(subject.getTodos()).resolves.toEqual([
        { id: '1', title: 'Buy milk', isCompleted: false, createdAt: new Date('2025-01-01T00:00:00Z') },
      ]);
    });

    it('propagates client errors', async () => {
      apiClient.getTodos.mockRejectedValue(new TodosApiError(500, 'boom'));

      await expect(subject.getTodos()).rejects.toBeInstanceOf(TodosApiError);
    });
  });

  describe('toggleTodo', () => {
    it('flips the completed flag and returns the updated model', async () => {
      apiClient.getTodo.mockResolvedValue(dto);
      apiClient.updateTodo.mockResolvedValue({ ...dto, completed: true });

      const result = await subject.toggleTodo(toTodoId(1));

      expect(apiClient.updateTodo).toHaveBeenCalledWith(1, { completed: true });
      expect(result.isCompleted).toBe(true);
    });

    it('throws TodoNotFoundError when the API returns 404', async () => {
      apiClient.getTodo.mockRejectedValue(new TodosApiError(404, ''));

      await expect(subject.toggleTodo(toTodoId(1))).rejects.toBeInstanceOf(TodoNotFoundError);
    });

    it('rethrows other API errors unchanged', async () => {
      apiClient.getTodo.mockRejectedValue(new TodosApiError(500, ''));

      await expect(subject.toggleTodo(toTodoId(1))).rejects.toMatchObject({ status: 500 });
    });
  });
});
```

Mock the client only. A repository test that starts an `msw` server is testing two layers.

---

## Shared fakes in the app: `apps/web/src/test/fakes.ts`

```ts
import type { TodosRepository } from '@acme/todos-repository';
import { vi } from 'vitest';

import type { Repositories } from '@/app/repositories';

export type FakeTodosRepository = { [K in keyof TodosRepository]: ReturnType<typeof vi.fn<TodosRepository[K]>> };

export function createFakeTodosRepository(): FakeTodosRepository {
  return {
    getTodos: vi.fn<TodosRepository['getTodos']>().mockResolvedValue([]),
    toggleTodo: vi.fn<TodosRepository['toggleTodo']>(),
  };
}

export function createFakeRepositories(overrides: Partial<Repositories> = {}): Repositories {
  return { todos: createFakeTodosRepository(), ...overrides };
}
```

Extend `renderWithProviders` from the **react-create-project** skill with a `repositories` option that wraps the tree in `RepositoriesProvider`, and add a `Suspense` boundary so `useSuspenseQuery` resolves:

```tsx
// apps/web/src/test/render.tsx (excerpt)
function Wrapper({ children }: { children: ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      <RepositoriesProvider value={repositories}>
        <Suspense fallback={<p>Loading</p>}>{children}</Suspense>
      </RepositoriesProvider>
    </QueryClientProvider>
  );
}
```

---

## Business logic: hooks with `renderHook`

```tsx
// apps/web/src/features/todos/api/useTodosQuery.test.tsx
import { toTodoId, type Todo } from '@acme/todos-repository';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { renderHook, waitFor } from '@testing-library/react';
import { Suspense, type ReactNode } from 'react';
import { describe, expect, it } from 'vitest';

import { RepositoriesProvider, type Repositories } from '@/app/repositories';
import { createFakeRepositories, createFakeTodosRepository } from '@/test/fakes';

import { useTodosQuery } from './useTodosQuery';

function createWrapper(repositories: Repositories) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });

  return function Wrapper({ children }: { children: ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        <RepositoriesProvider value={repositories}>
          <Suspense fallback={null}>{children}</Suspense>
        </RepositoriesProvider>
      </QueryClientProvider>
    );
  };
}

const todo: Todo = { id: toTodoId(1), title: 'Buy milk', isCompleted: false, createdAt: new Date(0) };

describe('useTodosQuery', () => {
  it('returns todos from the repository', async () => {
    const todos = createFakeTodosRepository();
    todos.getTodos.mockResolvedValue([todo]);

    const { result } = renderHook(() => useTodosQuery(), {
      wrapper: createWrapper(createFakeRepositories({ todos })),
    });

    await waitFor(() => {
      expect(result.current.data).toEqual([todo]);
    });
    expect(todos.getTodos).toHaveBeenCalledTimes(1);
  });
});
```

```tsx
// apps/web/src/features/todos/api/useToggleTodoMutation.test.tsx
import { toTodoId, type Todo } from '@acme/todos-repository';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, renderHook, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';
import { describe, expect, it } from 'vitest';

import { RepositoriesProvider } from '@/app/repositories';
import { createFakeRepositories, createFakeTodosRepository } from '@/test/fakes';

import { todosKeys } from './todosQueries';
import { useToggleTodoMutation } from './useToggleTodoMutation';

const todo: Todo = { id: toTodoId(1), title: 'Buy milk', isCompleted: true, createdAt: new Date(0) };

describe('useToggleTodoMutation', () => {
  it('calls the repository and invalidates the list', async () => {
    const todos = createFakeTodosRepository();
    todos.toggleTodo.mockResolvedValue(todo);
    const queryClient = new QueryClient();
    queryClient.setQueryData(todosKeys.list(), []);

    const { result } = renderHook(() => useToggleTodoMutation(), {
      wrapper: ({ children }: { children: ReactNode }) => (
        <QueryClientProvider client={queryClient}>
          <RepositoriesProvider value={createFakeRepositories({ todos })}>{children}</RepositoriesProvider>
        </QueryClientProvider>
      ),
    });

    act(() => {
      result.current.mutate(todo.id);
    });

    await waitFor(() => {
      expect(result.current.isSuccess).toBe(true);
    });
    expect(todos.toggleTodo).toHaveBeenCalledWith(todo.id);
    expect(queryClient.getQueryState(todosKeys.list())?.isInvalidated).toBe(true);
  });
});
```

---

## Presentation: view with Testing Library

```tsx
// apps/web/src/features/todos/components/TodosView.test.tsx
import { toTodoId, type Todo } from '@acme/todos-repository';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';

import { TodosView } from './TodosView';

const todos: Todo[] = [
  { id: toTodoId(1), title: 'Buy milk', isCompleted: false, createdAt: new Date(0) },
  { id: toTodoId(2), title: 'Walk dog', isCompleted: true, createdAt: new Date(0) },
];

describe('TodosView', () => {
  it('renders one checkbox per todo with its completion state', () => {
    render(<TodosView todos={todos} isToggling={false} errorMessage={null} onToggle={vi.fn()} />);

    expect(screen.getByRole('checkbox', { name: 'Buy milk' })).not.toBeChecked();
    expect(screen.getByRole('checkbox', { name: 'Walk dog' })).toBeChecked();
  });

  it('calls onToggle with the todo id when a checkbox is activated', async () => {
    const user = userEvent.setup();
    const onToggle = vi.fn();
    render(<TodosView todos={todos} isToggling={false} errorMessage={null} onToggle={onToggle} />);

    await user.click(screen.getByRole('checkbox', { name: 'Buy milk' }));

    expect(onToggle).toHaveBeenCalledWith(toTodoId(1));
  });

  it('disables checkboxes while toggling', () => {
    render(<TodosView todos={todos} isToggling errorMessage={null} onToggle={vi.fn()} />);

    expect(screen.getByRole('checkbox', { name: 'Buy milk' })).toBeDisabled();
  });

  it('shows an empty state when there are no todos', () => {
    render(<TodosView todos={[]} isToggling={false} errorMessage={null} onToggle={vi.fn()} />);

    expect(screen.getByText('No todos yet.')).toBeInTheDocument();
    expect(screen.queryByRole('list')).not.toBeInTheDocument();
  });

  it('announces an error message', () => {
    render(<TodosView todos={todos} isToggling={false} errorMessage="Nope" onToggle={vi.fn()} />);

    expect(screen.getByRole('alert')).toHaveTextContent('Nope');
  });
});
```

---

## Presentation: page with a fake repository

```tsx
// apps/web/src/features/todos/routes/TodosPage.test.tsx
import { toTodoId } from '@acme/todos-repository';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { createFakeRepositories, createFakeTodosRepository } from '@/test/fakes';
import { renderWithProviders } from '@/test/render';

import { TodosPage } from './TodosPage';

describe('TodosPage', () => {
  it('loads todos and toggles one', async () => {
    const user = userEvent.setup();
    const todos = createFakeTodosRepository();
    const todo = { id: toTodoId(1), title: 'Buy milk', isCompleted: false, createdAt: new Date(0) };
    todos.getTodos.mockResolvedValue([todo]);
    todos.toggleTodo.mockResolvedValue({ ...todo, isCompleted: true });

    renderWithProviders(<TodosPage />, { repositories: createFakeRepositories({ todos }) });

    await user.click(await screen.findByRole('checkbox', { name: 'Buy milk' }));

    expect(todos.toggleTodo).toHaveBeenCalledWith(todo.id);
  });
});
```

---

## Rules

- **Fake the immediate dependency only** — a hook test fakes the repository, never the API client or the network
- **Test mapping explicitly** — every `xFromDto` has a test covering trimming, date parsing, and optional fields
- **Query by role and accessible name** — `getByRole('checkbox', { name: 'Buy milk' })`; `getByTestId` is a last resort
- **Use `userEvent.setup()`** — never `fireEvent` for user interactions
- **`retry: false` in test `QueryClient`s** — failed queries resolve immediately instead of retrying for seconds
- **Colocate tests** — `Thing.test.tsx` next to `Thing.tsx`; packages mirror `src/`

## Anti-Patterns

| Anti-Pattern                                     | Problem                                      | Correct Approach                                         |
| ------------------------------------------------ | -------------------------------------------- | -------------------------------------------------------- |
| `vi.spyOn(globalThis, 'fetch')` in a client test | Brittle; misses headers and URL construction | `msw` handlers with `onUnhandledRequest: 'error'`        |
| `msw` in a repository or hook test               | Tests two layers; slow and duplicated        | Typed `vi.fn()` fake of the layer below                  |
| `vi.mock('@acme/todos-repository')`              | Module mocks hide the injection seam         | Pass a fake through `RepositoriesProvider`               |
| Asserting on class names or DOM structure        | Breaks on every refactor                     | Assert on roles, names, states, and callbacks            |
| One shared `QueryClient` across tests            | Cache leaks between tests                    | New `QueryClient` per test via `createTestQueryClient()` |
| Testing `XPage` without `Suspense`               | `useSuspenseQuery` throws a promise          | `renderWithProviders` includes a `Suspense` boundary     |
