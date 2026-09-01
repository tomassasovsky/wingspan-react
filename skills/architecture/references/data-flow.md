# Data Flow Walkthrough

Complete code for the `todos` request path, one file per layer. Replace `@acme` with the workspace scope.

---

## Data layer: `packages/todos-api-client`

### `src/dto/todo-dto.ts`

```ts
import { z } from 'zod';

/** Wire format of a todo. Field names match the API exactly. */
export const todoDtoSchema = z.object({
  id: z.number().int(),
  title: z.string(),
  completed: z.boolean(),
  created_at: z.iso.datetime(),
});

export type TodoDto = z.infer<typeof todoDtoSchema>;

export const updateTodoBodySchema = todoDtoSchema.pick({ title: true, completed: true }).partial();

export type UpdateTodoBody = z.infer<typeof updateTodoBodySchema>;
```

### `src/errors.ts`

```ts
export class TodosApiError extends Error {
  readonly status: number;
  readonly body: string;

  constructor(status: number, body: string) {
    super(`Todos API request failed with status ${status}`);
    this.name = 'TodosApiError';
    this.status = status;
    this.body = body;
  }
}
```

### `src/todos-api-client.ts`

```ts
import type { ZodType } from 'zod';

import { todoDtoSchema, type TodoDto, type UpdateTodoBody } from './dto/todo-dto';
import { TodosApiError } from './errors';

export type TodosApiClientOptions = {
  baseUrl: string;
  /** Injected for tests and for platforms with a custom fetch. */
  fetch?: typeof fetch;
};

export type TodosApiClient = {
  getTodos(): Promise<TodoDto[]>;
  getTodo(id: number): Promise<TodoDto>;
  updateTodo(id: number, body: UpdateTodoBody): Promise<TodoDto>;
};

export function createTodosApiClient({ baseUrl, fetch: fetchFn = fetch }: TodosApiClientOptions): TodosApiClient {
  async function request<T>(path: string, init: RequestInit, schema: ZodType<T>): Promise<T> {
    const response = await fetchFn(`${baseUrl}${path}`, {
      ...init,
      headers: { accept: 'application/json', 'content-type': 'application/json', ...init.headers },
    });

    if (!response.ok) {
      throw new TodosApiError(response.status, await response.text());
    }

    return schema.parse(await response.json());
  }

  return {
    getTodos: () => request('/todos', { method: 'GET' }, todoDtoSchema.array()),
    getTodo: (id) => request(`/todos/${id}`, { method: 'GET' }, todoDtoSchema),
    updateTodo: (id, body) =>
      request(`/todos/${id}`, { method: 'PATCH', body: JSON.stringify(body) }, todoDtoSchema),
  };
}
```

### `src/index.ts`

```ts
export { todoDtoSchema, updateTodoBodySchema, type TodoDto, type UpdateTodoBody } from './dto/todo-dto';
export { TodosApiError } from './errors';
export { createTodosApiClient, type TodosApiClient, type TodosApiClientOptions } from './todos-api-client';
```

---

## Domain layer: `packages/todos-repository`

### `src/models/todo.ts`

```ts
import type { TodoDto } from '@acme/todos-api-client';

/** Branded id so a TodoId is never confused with another entity's id. */
export type TodoId = string & { readonly __brand: 'TodoId' };

export function toTodoId(value: number | string): TodoId {
  return String(value) as TodoId;
}

/** Domain model. Field names describe meaning, not the wire format. */
export type Todo = {
  id: TodoId;
  title: string;
  isCompleted: boolean;
  createdAt: Date;
};

export function todoFromDto(dto: TodoDto): Todo {
  return {
    id: toTodoId(dto.id),
    title: dto.title.trim(),
    isCompleted: dto.completed,
    createdAt: new Date(dto.created_at),
  };
}
```

### `src/errors.ts`

```ts
import type { TodoId } from './models/todo';

export class TodoNotFoundError extends Error {
  readonly id: TodoId;

  constructor(id: TodoId) {
    super(`Todo ${id} was not found`);
    this.name = 'TodoNotFoundError';
    this.id = id;
  }
}
```

### `src/todos-repository.ts`

```ts
import { TodosApiError, type TodosApiClient } from '@acme/todos-api-client';

import { TodoNotFoundError } from './errors';
import { todoFromDto, type Todo, type TodoId } from './models/todo';

export type TodosRepository = {
  getTodos(): Promise<Todo[]>;
  toggleTodo(id: TodoId): Promise<Todo>;
};

export type TodosRepositoryDependencies = { apiClient: TodosApiClient };

export function createTodosRepository({ apiClient }: TodosRepositoryDependencies): TodosRepository {
  return {
    async getTodos() {
      const dtos = await apiClient.getTodos();
      return dtos.map(todoFromDto);
    },

    async toggleTodo(id) {
      try {
        const current = await apiClient.getTodo(Number(id));
        const updated = await apiClient.updateTodo(current.id, { completed: !current.completed });
        return todoFromDto(updated);
      } catch (error) {
        if (error instanceof TodosApiError && error.status === 404) {
          throw new TodoNotFoundError(id);
        }
        throw error;
      }
    },
  };
}
```

### `src/index.ts`

```ts
export { TodoNotFoundError } from './errors';
export { todoFromDto, toTodoId, type Todo, type TodoId } from './models/todo';
export { createTodosRepository, type TodosRepository, type TodosRepositoryDependencies } from './todos-repository';
```

---

## Composition root: `apps/web/src/app`

### `config.ts`

```ts
import { z } from 'zod';

const envSchema = z.object({ VITE_API_BASE_URL: z.url() });

export type AppConfig = { apiBaseUrl: string };

export function loadConfig(env: Record<string, unknown> = import.meta.env): AppConfig {
  const parsed = envSchema.parse(env);
  return { apiBaseUrl: parsed.VITE_API_BASE_URL };
}
```

### `repositories.tsx`

```tsx
import { createContext, use, type ReactNode } from 'react';
import type { TodosRepository } from '@acme/todos-repository';

export type Repositories = { todos: TodosRepository };

const RepositoriesContext = createContext<Repositories | null>(null);

export function RepositoriesProvider({ value, children }: { value: Repositories; children: ReactNode }) {
  return <RepositoriesContext value={value}>{children}</RepositoriesContext>;
}

export function useRepositories(): Repositories {
  const repositories = use(RepositoriesContext);
  if (repositories === null) {
    throw new Error('useRepositories must be used inside RepositoriesProvider');
  }
  return repositories;
}
```

### `bootstrap.ts`

```ts
import { createTodosApiClient } from '@acme/todos-api-client';
import { createTodosRepository } from '@acme/todos-repository';

import type { AppConfig } from './config';
import type { Repositories } from './repositories';

/** The only file in the app that may import a data package. */
export function createRepositories(config: AppConfig): Repositories {
  const todosApiClient = createTodosApiClient({ baseUrl: config.apiBaseUrl });

  return {
    todos: createTodosRepository({ apiClient: todosApiClient }),
  };
}
```

### `providers.tsx`

```tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

import { RepositoriesProvider, type Repositories } from './repositories';

export type ProvidersProps = {
  repositories: Repositories;
  queryClient: QueryClient;
  children: ReactNode;
};

export function Providers({ repositories, queryClient, children }: ProvidersProps) {
  return (
    <QueryClientProvider client={queryClient}>
      <RepositoriesProvider value={repositories}>{children}</RepositoriesProvider>
    </QueryClientProvider>
  );
}
```

### `router.tsx`

```tsx
import { createBrowserRouter } from 'react-router';

import { RootLayout } from './RootLayout';
import { RouteError } from './RouteError';

export const router = createBrowserRouter([
  {
    path: '/',
    Component: RootLayout,
    ErrorBoundary: RouteError,
    children: [
      {
        index: true,
        lazy: async () => {
          const { TodosPage } = await import('@/features/todos');
          return { Component: TodosPage };
        },
      },
    ],
  },
]);
```

`RootLayout` renders `<Suspense fallback={<Spinner />}><Outlet /></Suspense>` so `useSuspenseQuery` has a boundary; `RouteError` renders thrown errors via `useRouteError()`.

### `main.tsx`

```tsx
import { QueryClient } from '@tanstack/react-query';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { RouterProvider } from 'react-router';

import { createRepositories } from './app/bootstrap';
import { loadConfig } from './app/config';
import { Providers } from './app/providers';
import { router } from './app/router';

const root = document.getElementById('root');
if (root === null) {
  throw new Error('Missing #root element');
}

const repositories = createRepositories(loadConfig());
const queryClient = new QueryClient({ defaultOptions: { queries: { staleTime: 60_000 } } });

createRoot(root).render(
  <StrictMode>
    <Providers repositories={repositories} queryClient={queryClient}>
      <RouterProvider router={router} />
    </Providers>
  </StrictMode>,
);
```

---

## Business logic: `apps/web/src/features/todos/api`

### `todosQueries.ts`

```ts
import { queryOptions } from '@tanstack/react-query';
import type { TodosRepository } from '@acme/todos-repository';

export const todosKeys = {
  all: ['todos'] as const,
  lists: () => [...todosKeys.all, 'list'] as const,
  list: () => [...todosKeys.lists()] as const,
};

export function todosListOptions(repository: TodosRepository) {
  return queryOptions({
    queryKey: todosKeys.list(),
    queryFn: () => repository.getTodos(),
  });
}
```

### `useTodosQuery.ts`

```ts
import { useSuspenseQuery } from '@tanstack/react-query';

import { useRepositories } from '@/app/repositories';

import { todosListOptions } from './todosQueries';

export function useTodosQuery() {
  const { todos } = useRepositories();
  return useSuspenseQuery(todosListOptions(todos));
}
```

### `useToggleTodoMutation.ts`

```ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import type { TodoId } from '@acme/todos-repository';

import { useRepositories } from '@/app/repositories';

import { todosKeys } from './todosQueries';

export function useToggleTodoMutation() {
  const { todos } = useRepositories();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: TodoId) => todos.toggleTodo(id),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: todosKeys.lists() });
    },
  });
}
```

---

## Presentation: `apps/web/src/features/todos`

### `routes/TodosPage.tsx`

```tsx
import { useToggleTodoMutation } from '../api/useToggleTodoMutation';
import { useTodosQuery } from '../api/useTodosQuery';
import { TodosView } from '../components/TodosView';

export function TodosPage() {
  const { data: todos } = useTodosQuery();
  const toggle = useToggleTodoMutation();

  return (
    <TodosView
      todos={todos}
      isToggling={toggle.isPending}
      errorMessage={toggle.error?.message ?? null}
      onToggle={(id) => toggle.mutate(id)}
    />
  );
}
```

### `components/TodosView.tsx`

```tsx
import type { Todo, TodoId } from '@acme/todos-repository';
import { Checkbox } from '@acme/ui';

export type TodosViewProps = {
  todos: readonly Todo[];
  isToggling: boolean;
  errorMessage: string | null;
  onToggle: (id: TodoId) => void;
};

export function TodosView({ todos, isToggling, errorMessage, onToggle }: TodosViewProps) {
  return (
    <section aria-labelledby="todos-heading">
      <h1 id="todos-heading">Todos</h1>
      {errorMessage !== null && <p role="alert">{errorMessage}</p>}
      {todos.length === 0 ? (
        <p>No todos yet.</p>
      ) : (
        <ul aria-label="Todos">
          {todos.map((todo) => (
            <li key={todo.id}>
              <Checkbox
                checked={todo.isCompleted}
                disabled={isToggling}
                onCheckedChange={() => {
                  onToggle(todo.id);
                }}
              >
                {todo.title}
              </Checkbox>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
```

### `index.ts`

```ts
export { todosKeys } from './api/todosQueries';
export { TodosPage } from './routes/TodosPage';
```

---

## Sequence

1. Router matches `/`, lazy-loads `@/features/todos`, renders `TodosPage`
2. `useTodosQuery` reads `todos` from `useRepositories()` and suspends on `todosListOptions(todos)`
3. `createTodosRepository.getTodos` calls `apiClient.getTodos()` and maps each DTO through `todoFromDto`
4. `createTodosApiClient.getTodos` fetches `${baseUrl}/todos`, throws `TodosApiError` on a non-2xx status, and parses the body with `todoDtoSchema.array()`
5. The models are cached under `['todos', 'list']`; `TodosView` renders them
6. Toggling calls `toggle.mutate(id)`; on success the list key is invalidated and step 2 repeats with fresh data
