# React Router v7 Data Mode

Complete setup for a Vite SPA using `react-router` v7 with `createBrowserRouter`, lazy route modules, loaders backed by `@tanstack/react-query`, and actions.

## App Wiring

```tsx
// src/app/queryClient.ts
import { createQueryClient } from './createQueryClient';

// One client for the app; loaders import it, components read it through QueryClientProvider.
export const queryClient = createQueryClient();
```

```tsx
// src/app/AppProviders.tsx
import { QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { queryClient } from './queryClient';
import { todoRepository } from '@/lib/repositories';
import { TodoRepositoryProvider } from '@/features/todos/hooks/useTodoRepository';

export function AppProviders({ children }: { children: ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      <TodoRepositoryProvider repository={todoRepository}>{children}</TodoRepositoryProvider>
    </QueryClientProvider>
  );
}
```

```tsx
// src/main.tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { RouterProvider } from 'react-router';
import { AppProviders } from './app/AppProviders';
import { router } from './app/router';

createRoot(document.getElementById('root') as HTMLElement).render(
  <StrictMode>
    <AppProviders>
      <RouterProvider router={router} />
    </AppProviders>
  </StrictMode>,
);
```

## Router with Nested Layouts

```tsx
// src/app/router.tsx
import { createBrowserRouter } from 'react-router';
import { RootErrorBoundary } from './RootErrorBoundary';
import { RootLayout } from './RootLayout';

export const routes = [
  {
    path: '/',
    Component: RootLayout,
    ErrorBoundary: RootErrorBoundary,
    HydrateFallback: () => null,
    children: [
      { index: true, lazy: () => import('@/features/home/routes/home') },
      {
        // Public-only layout: redirects signed-in users away from /login
        lazy: () => import('@/features/auth/routes/publicLayout'),
        children: [
          { path: 'login', lazy: () => import('@/features/auth/routes/login') },
          { path: 'signup', lazy: () => import('@/features/auth/routes/signup') },
        ],
      },
      {
        // Protected layout: requires a session and renders the app shell
        lazy: () => import('@/features/app-shell/routes/appLayout'),
        children: [
          {
            path: 'todos',
            lazy: () => import('@/features/todos/routes/todosLayout'),
            children: [
              { index: true, lazy: () => import('@/features/todos/routes/todoList') },
              { path: 'new', lazy: () => import('@/features/todos/routes/todoNew') },
              { path: ':todoId', lazy: () => import('@/features/todos/routes/todoDetail') },
            ],
          },
          { path: 'settings', lazy: () => import('@/features/settings/routes/settings') },
        ],
      },
      { path: '*', lazy: () => import('@/features/not-found/routes/notFound') },
    ],
  },
];

export const router = createBrowserRouter(routes);
```

Export `routes` separately so tests can build a `createMemoryRouter` from the same tree.

Pathless layout routes (no `path`) group children under a shared loader and component without adding a URL segment.

## Root Layout and Error Boundary

```tsx
// src/app/RootLayout.tsx
import { Outlet, ScrollRestoration, useNavigation } from 'react-router';

export function RootLayout() {
  const navigation = useNavigation();
  return (
    <>
      <a href="#main">Skip to content</a>
      <div aria-live="polite" aria-busy={navigation.state !== 'idle'} />
      <main id="main">
        <Outlet />
      </main>
      <ScrollRestoration />
    </>
  );
}
```

```tsx
// src/app/RootErrorBoundary.tsx
import { isRouteErrorResponse, useRouteError } from 'react-router';

export function RootErrorBoundary() {
  const error = useRouteError();

  if (isRouteErrorResponse(error)) {
    return (
      <section role="alert">
        <h1>{error.status === 404 ? 'Page not found' : `Error ${error.status}`}</h1>
        <p>{typeof error.data === 'object' && error.data !== null && 'message' in error.data
          ? String(error.data.message)
          : error.statusText}</p>
      </section>
    );
  }

  return (
    <section role="alert">
      <h1>Something went wrong</h1>
      <p>{error instanceof Error ? error.message : 'Unknown error'}</p>
    </section>
  );
}
```

## Layout Route Modules

```tsx
// src/features/app-shell/routes/appLayout.tsx
import { Outlet, useLoaderData, type LoaderFunctionArgs } from 'react-router';
import { requireUser } from '@/features/auth/lib/requireUser';
import { AppShell } from '../components/AppShell';

export async function loader({ request }: LoaderFunctionArgs) {
  const user = await requireUser(request);
  return { user };
}

export function Component() {
  const { user } = useLoaderData<typeof loader>();
  return (
    <AppShell user={user}>
      <Outlet />
    </AppShell>
  );
}
```

```tsx
// src/features/auth/routes/publicLayout.tsx
import { Outlet, redirect } from 'react-router';
import { queryClient } from '@/app/queryClient';
import { sessionQueryOptions } from '../api/useSessionQuery';

export async function loader() {
  const user = await queryClient.ensureQueryData(sessionQueryOptions());
  if (user) throw redirect('/');
  return null;
}

export function Component() {
  return <Outlet />;
}
```

## Route Module Pattern

Every route module exports a subset of these names. Nothing else is exported from a route module.

| Export             | Purpose                                                          |
| ------------------ | ---------------------------------------------------------------- |
| `loader`           | Load data before render; throw `redirect` or `data` for errors   |
| `action`           | Handle `Form`/`useFetcher` submissions                           |
| `Component`        | Route UI; wires loader data and params into a `View`             |
| `ErrorBoundary`    | Renders thrown errors for this route subtree                     |
| `HydrateFallback`  | Shown while `clientLoader` runs on initial load (framework mode) |
| `shouldRevalidate` | Skip loader re-runs for irrelevant navigations                   |

### List Route with Search-Param Loader

```tsx
// src/features/todos/routes/todoList.tsx
import { useLoaderData, type LoaderFunctionArgs } from 'react-router';
import { z } from 'zod';
import { queryClient } from '@/app/queryClient';
import { todoRepository } from '@/lib/repositories';
import { requireUser } from '@/features/auth/lib/requireUser';
import { todosQueryOptions } from '../api/useTodosQuery';
import { TodoListView } from '../components/TodoListView';

const filtersSchema = z.object({
  status: z.enum(['all', 'open', 'done']).catch('all'),
  page: z.coerce.number().int().min(1).catch(1),
});

export async function loader({ request }: LoaderFunctionArgs) {
  await requireUser(request);
  const filters = filtersSchema.parse(Object.fromEntries(new URL(request.url).searchParams));
  await queryClient.ensureQueryData(todosQueryOptions(todoRepository, filters));
  return { filters };
}

export function Component() {
  const { filters } = useLoaderData<typeof loader>();
  return <TodoListView filters={filters} />;
}
```

`TodoListView` calls `useSuspenseQuery(todosQueryOptions(repository, filters))`; the loader already warmed the cache, so it renders synchronously.

### Create Route with `Form` and Action

```tsx
// src/features/todos/routes/todoNew.tsx
import { Form, redirect, useActionData, useNavigation, type ActionFunctionArgs } from 'react-router';
import { z } from 'zod';
import { queryClient } from '@/app/queryClient';
import { todoRepository } from '@/lib/repositories';
import { requireUser } from '@/features/auth/lib/requireUser';
import { paths } from '@/app/paths';
import { todoKeys } from '../api/todoKeys';
import { createTodoSchema } from '../createTodoSchema';

export async function action({ request }: ActionFunctionArgs) {
  await requireUser(request);
  const parsed = createTodoSchema.safeParse(Object.fromEntries(await request.formData()));
  if (!parsed.success) {
    return { fieldErrors: z.flattenError(parsed.error).fieldErrors };
  }
  const todo = await todoRepository.createTodo(parsed.data);
  await queryClient.invalidateQueries({ queryKey: todoKeys.lists() });
  return redirect(paths.todo(todo.id));
}

export function Component() {
  const actionData = useActionData<typeof action>();
  const navigation = useNavigation();
  const isSubmitting = navigation.state === 'submitting';
  const titleError = actionData?.fieldErrors.title?.[0];

  return (
    <Form method="post" noValidate aria-busy={isSubmitting}>
      <label htmlFor="title">Title</label>
      <input
        id="title"
        name="title"
        aria-invalid={titleError ? true : undefined}
        aria-describedby={titleError ? 'title-error' : undefined}
      />
      {titleError ? <p id="title-error" role="alert">{titleError}</p> : null}
      <button type="submit" disabled={isSubmitting}>Create</button>
    </Form>
  );
}
```

Use `Form` + `action` for navigational submissions (create then go to the new resource). Use `react-hook-form` + a mutation for rich in-place forms; the `react-forms` skill covers that.

### Non-Navigational Mutations with `useFetcher`

```tsx
// src/features/todos/components/TodoToggle.tsx
import { useFetcher } from 'react-router';

export function TodoToggle({ todoId, completed }: { todoId: string; completed: boolean }) {
  const fetcher = useFetcher();
  const optimistic = fetcher.formData ? fetcher.formData.get('completed') === 'true' : completed;

  return (
    <fetcher.Form method="post" action={`/todos/${todoId}`}>
      <input type="hidden" name="intent" value="toggle" />
      <input type="hidden" name="completed" value={String(!completed)} />
      <button type="submit" aria-pressed={optimistic}>
        {optimistic ? 'Mark open' : 'Mark done'}
      </button>
    </fetcher.Form>
  );
}
```

## Typed Route Helpers

```ts
// src/app/paths.ts
type TodoStatus = 'open' | 'done';

function withSearch(path: string, params: Record<string, string | number | undefined>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) search.set(key, String(value));
  }
  const query = search.toString();
  return query ? `${path}?${query}` : path;
}

export const paths = {
  home: () => '/',
  login: (redirectTo?: string) => withSearch('/login', { redirectTo }),
  signup: () => '/signup',
  todos: (filters: { status?: TodoStatus; page?: number } = {}) => withSearch('/todos', filters),
  todoNew: () => '/todos/new',
  todo: (todoId: string) => `/todos/${encodeURIComponent(todoId)}`,
  settings: () => '/settings',
} as const;

export type PathKey = keyof typeof paths;
```

```ts
// src/app/paths.test.ts
import { describe, expect, it } from 'vitest';
import { paths } from './paths';

describe('paths', () => {
  it('encodes ids', () => {
    expect(paths.todo('a/b')).toBe('/todos/a%2Fb');
  });

  it('omits undefined search params', () => {
    expect(paths.todos({ status: 'done' })).toBe('/todos?status=done');
    expect(paths.todos()).toBe('/todos');
  });

  it('encodes redirectTo', () => {
    expect(paths.login('/todos?status=done')).toBe('/login?redirectTo=%2Ftodos%3Fstatus%3Ddone');
  });
});
```

```ts
// src/lib/router/useTypedParams.ts
import { useParams } from 'react-router';
import type { z } from 'zod';

export function useTypedParams<Schema extends z.ZodType>(schema: Schema): z.output<Schema> {
  return schema.parse(useParams());
}
```

```tsx
const { todoId } = useTypedParams(z.object({ todoId: z.string().min(1) }));
```

## URL State Hook

```ts
// src/features/todos/hooks/useTodoFilters.ts
import { useSearchParams } from 'react-router';
import { z } from 'zod';

const filtersSchema = z.object({
  status: z.enum(['all', 'open', 'done']).catch('all'),
  page: z.coerce.number().int().min(1).catch(1),
});

export type TodoFilters = z.infer<typeof filtersSchema>;

export function useTodoFilters() {
  const [searchParams, setSearchParams] = useSearchParams();
  const filters = filtersSchema.parse(Object.fromEntries(searchParams));

  const setFilters = (next: Partial<TodoFilters>) => {
    setSearchParams((current) => {
      const merged = { ...filtersSchema.parse(Object.fromEntries(current)), ...next };
      const params = new URLSearchParams();
      if (merged.status !== 'all') params.set('status', merged.status);
      if (merged.page !== 1) params.set('page', String(merged.page));
      return params;
    });
  };

  return { filters, setFilters };
}
```

Defaults are omitted from the URL so `/todos` stays canonical. The `setSearchParams` updater form reads the current params so two rapid updates do not clobber each other.

## Safe Redirect Targets

```ts
// src/lib/router/safeRedirect.ts
export function safeRedirect(value: string | null, fallback = '/'): string {
  if (!value || !value.startsWith('/') || value.startsWith('//') || value.includes('\\')) return fallback;
  return value;
}
```

```ts
// src/lib/router/safeRedirect.test.ts
import { describe, expect, it } from 'vitest';
import { safeRedirect } from './safeRedirect';

describe('safeRedirect', () => {
  it.each([
    ['/todos?status=done', '/todos?status=done'],
    ['//evil.example', '/'],
    ['https://evil.example', '/'],
    ['/\\evil.example', '/'],
    [null, '/'],
  ])('%s -> %s', (input, expected) => {
    expect(safeRedirect(input)).toBe(expected);
  });
});
```

The login route reads `redirectTo` from search params and navigates to `safeRedirect(redirectTo, paths.home())` after a successful sign-in.

## Navigation Hooks

| Hook              | Use for                                                         |
| ----------------- | --------------------------------------------------------------- |
| `useNavigate`     | Imperative navigation after an event; prefer `Link`/`Form`      |
| `useNavigation`   | Global pending state: `navigation.state`, `navigation.formData` |
| `useSearchParams` | Read and write URL state                                        |
| `useLocation`     | Current path and `location.state`                               |
| `useMatches`      | Breadcrumbs from route `handle` data                            |
| `useBlocker`      | Unsaved-changes guard                                           |
| `useRevalidator`  | Re-run loaders after an external event                          |

Never pass entities through `navigate(path, { state })`; the state is lost on refresh and deep links. Pass ids and re-read from the cache.

## `shouldRevalidate`

Loaders re-run after every action and on search-param changes. Skip needless re-runs:

```ts
export const shouldRevalidate: ShouldRevalidateFunction = ({ currentUrl, nextUrl, defaultShouldRevalidate }) => {
  if (currentUrl.pathname === nextUrl.pathname && currentUrl.search !== nextUrl.search) return false;
  return defaultShouldRevalidate;
};
```

Use this on layout routes whose data does not depend on search params.
