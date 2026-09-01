# TanStack Query

Server state belongs in `@tanstack/react-query` v5. This reference covers configuration and the patterns that go beyond a single `useQuery`.

## `QueryClient` Defaults

Set defaults once. Every query inherits them; override per query only with a reason.

```ts
// src/app/queryClient.ts
import { QueryClient } from '@tanstack/react-query';

export function createQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 60 * 1000,
        gcTime: 5 * 60 * 1000,
        retry: (failureCount, error) => {
          if (error instanceof HttpError && error.status >= 400 && error.status < 500) return false;
          return failureCount < 2;
        },
        refetchOnWindowFocus: false,
        throwOnError: (error) => error instanceof HttpError && error.status >= 500,
      },
      mutations: {
        retry: 0,
      },
    },
  });
}

export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'HttpError';
  }
}
```

| Option                 | Default here  | Reason                                                       |
| ---------------------- | ------------- | ------------------------------------------------------------ |
| `staleTime`            | 60 s          | Avoid refetch storms when several components mount together  |
| `gcTime`               | 5 min         | Keep data for back navigation without holding memory forever |
| `retry`                | 2, not on 4xx | Client errors will not succeed on retry                      |
| `refetchOnWindowFocus` | `false`       | Opt in per query for live data                               |
| `throwOnError`         | 5xx only      | Server failures reach the nearest error boundary             |

## Query Key Factories

One factory per resource. Keys are hierarchical so invalidation targets a prefix.

```ts
export const todoKeys = {
  all: ['todos'] as const,
  lists: () => [...todoKeys.all, 'list'] as const,
  list: (filters: TodoFilters) => [...todoKeys.lists(), filters] as const,
  details: () => [...todoKeys.all, 'detail'] as const,
  detail: (id: string) => [...todoKeys.details(), id] as const,
};
```

| Call                                                   | Invalidates             |
| ------------------------------------------------------ | ----------------------- |
| `invalidateQueries({ queryKey: todoKeys.all })`        | Every todo query        |
| `invalidateQueries({ queryKey: todoKeys.lists() })`    | Every list, any filters |
| `invalidateQueries({ queryKey: todoKeys.detail(id) })` | One detail              |

Filters in keys are plain objects. Query hashes objects structurally, so `{ status: 'done', page: 1 }` and `{ page: 1, status: 'done' }` share a cache entry.

## `queryOptions` Helper

Define options once and reuse them in hooks, loaders, prefetching, and `setQueryData` with full type inference.

```ts
import { queryOptions } from '@tanstack/react-query';

export function todoQueryOptions(repository: TodoRepository, id: string) {
  return queryOptions({
    queryKey: todoKeys.detail(id),
    queryFn: ({ signal }) => repository.getTodo(id, { signal }),
  });
}

// Hook
export function useTodoQuery(id: string) {
  const repository = useTodoRepository();
  return useQuery(todoQueryOptions(repository, id));
}

// Typed cache read: `todo` is `Todo | undefined`
const todo = queryClient.getQueryData(todoQueryOptions(repository, id).queryKey);
```

Always pass `signal` to the repository so navigating away cancels the request.

## Suspense

Use `useSuspenseQuery` when the component cannot render without the data. It returns `data` as non-nullable and defers loading and error UI to boundaries.

```tsx
// src/features/todos/routes/TodoDetailPage.tsx
import { Suspense } from 'react';
import { ErrorBoundary } from 'react-error-boundary';
import { QueryErrorResetBoundary, useSuspenseQuery } from '@tanstack/react-query';

function TodoDetail({ id }: { id: string }) {
  const repository = useTodoRepository();
  const { data: todo } = useSuspenseQuery(todoQueryOptions(repository, id));
  return <TodoView todo={todo} />;
}

export function TodoDetailPage({ id }: { id: string }) {
  return (
    <QueryErrorResetBoundary>
      {({ reset }) => (
        <ErrorBoundary
          onReset={reset}
          fallbackRender={({ resetErrorBoundary }) => (
            <ErrorView onRetry={resetErrorBoundary} />
          )}
        >
          <Suspense fallback={<TodoDetailSkeleton />}>
            <TodoDetail id={id} />
          </Suspense>
        </ErrorBoundary>
      )}
    </QueryErrorResetBoundary>
  );
}
```

| Use                  | When                                                          |
| -------------------- | ------------------------------------------------------------- |
| `useSuspenseQuery`   | Data is required to render; route already has boundaries      |
| `useQuery`           | Data is optional, or the component owns its own loading state |
| `useQueries`         | Several independent queries in one component                  |
| `useSuspenseQueries` | Several required queries that should suspend together         |

Never use `useSuspenseQuery` with `enabled: false`; it is unsupported. Use `useQuery` for conditional fetching.

## Prefetching

Prefetch in route loaders so the page renders with data on first paint.

```ts
// React Router v7 loader
export async function loader({ params }: LoaderFunctionArgs) {
  const { todoId } = paramsSchema.parse(params);
  await queryClient.ensureQueryData(todoQueryOptions(todoRepository, todoId));
  return null;
}
```

| Method            | Behavior                                               |
| ----------------- | ------------------------------------------------------ |
| `prefetchQuery`   | Fetch if stale; never throws; returns `void`           |
| `ensureQueryData` | Return cached data or fetch; throws on error           |
| `fetchQuery`      | Always fetch when stale; throws on error; returns data |

Prefetch on hover for likely next pages:

```tsx
<Link
  to={`/todos/${todo.id}`}
  onMouseEnter={() => queryClient.prefetchQuery(todoQueryOptions(repository, todo.id))}
>
  {todo.title}
</Link>
```

## Pagination

Keep the page in the URL. Use `keepPreviousData` so the old page stays visible while the next loads.

```ts
import { keepPreviousData, queryOptions, useQuery } from '@tanstack/react-query';

export function todosPageQueryOptions(repository: TodoRepository, page: number) {
  return queryOptions({
    queryKey: todoKeys.list({ page }),
    queryFn: ({ signal }) => repository.getTodosPage(page, { signal }),
    placeholderData: keepPreviousData,
  });
}

export function useTodosPageQuery(page: number) {
  const repository = useTodoRepository();
  return useQuery(todosPageQueryOptions(repository, page));
}
```

`isPlaceholderData` is `true` while showing the previous page; use it to disable the "next" button.

## Infinite Queries

```ts
import { infiniteQueryOptions, useInfiniteQuery } from '@tanstack/react-query';

interface TodoPage {
  items: Todo[];
  nextCursor: string | null;
}

export function todosInfiniteQueryOptions(repository: TodoRepository) {
  return infiniteQueryOptions({
    queryKey: todoKeys.list({ mode: 'infinite' }),
    queryFn: ({ pageParam, signal }): Promise<TodoPage> =>
      repository.getTodosAfter(pageParam, { signal }),
    initialPageParam: null as string | null,
    getNextPageParam: (lastPage) => lastPage.nextCursor,
  });
}

export function useTodosInfiniteQuery() {
  const repository = useTodoRepository();
  return useInfiniteQuery(todosInfiniteQueryOptions(repository));
}
```

```tsx
const { data, fetchNextPage, hasNextPage, isFetchingNextPage } = useTodosInfiniteQuery();
const todos = data?.pages.flatMap((page) => page.items) ?? [];
```

Flatten pages in the component or with `select`; never store the flattened array anywhere.

## Error Handling

| Layer     | Mechanism                                                        |
| --------- | ---------------------------------------------------------------- |
| Transport | Repository throws a typed `HttpError`; never returns `undefined` |
| Query     | `retry` skips 4xx; `throwOnError` escalates 5xx                  |
| Component | `isError` + `error` for inline recoverable errors                |
| Route     | `ErrorBoundary` + `QueryErrorResetBoundary` for fatal errors     |
| Mutation  | `onError` rolls back optimistic state; UI reads `mutation.error` |

Register the error type once so `error` is typed everywhere:

```ts
// src/app/queryClient.ts
declare module '@tanstack/react-query' {
  interface Register {
    defaultError: HttpError;
  }
}
```

## Hydration in Next.js App Router

Fetch on the server, dehydrate, and hydrate on the client. One `QueryClient` per request on the server; a singleton in the browser.

```ts
// src/app/getQueryClient.ts
import { QueryClient, isServer } from '@tanstack/react-query';
import { cache } from 'react';

function makeQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: { staleTime: 60 * 1000 },
    },
  });
}

let browserQueryClient: QueryClient | undefined;

export const getQueryClient = cache((): QueryClient => {
  if (isServer) return makeQueryClient();
  browserQueryClient ??= makeQueryClient();
  return browserQueryClient;
});
```

```tsx
// src/app/providers.tsx
'use client';

import { QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { getQueryClient } from './getQueryClient';

export function Providers({ children }: { children: ReactNode }) {
  const queryClient = getQueryClient();
  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
}
```

```tsx
// src/app/todos/page.tsx (server component)
import { HydrationBoundary, dehydrate } from '@tanstack/react-query';
import { getQueryClient } from '../getQueryClient';
import { todosQueryOptions } from '@/features/todos/api/useTodosQuery';
import { TodoList } from '@/features/todos/components/TodoList';
import { todoRepository } from '@/lib/repositories';

export default async function TodosPage() {
  const queryClient = getQueryClient();
  await queryClient.prefetchQuery(todosQueryOptions(todoRepository, {}));

  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      <TodoList />
    </HydrationBoundary>
  );
}
```

`TodoList` is a client component calling `useTodosQuery({})`. It renders immediately from the hydrated cache with no client fetch.

| Rule                                                     | Reason                                               |
| -------------------------------------------------------- | ---------------------------------------------------- |
| Never create `QueryClient` at module scope on the server | Requests would share a cache and leak data           |
| Wrap `getQueryClient` in `cache()`                       | Same client across one request's server components   |
| `staleTime > 0` on the server                            | Prevents an immediate client refetch after hydration |
| Use `prefetchQuery`, not `fetchQuery`, in pages          | Errors surface in the client query, not as a 500     |
