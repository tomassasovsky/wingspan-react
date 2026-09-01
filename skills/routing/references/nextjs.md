# Next.js App Router

Complete routing setup for a Next.js app: file tree, layouts, pages with typed params, `loading`/`error`/`not-found`, an auth redirect in `middleware.ts`, client navigation, and search-param filters.

## App Tree

```text
src/
  middleware.ts
  app/
    layout.tsx                    # Root layout: html, body, providers
    not-found.tsx                 # Global 404
    error.tsx                     # Global error boundary
    (marketing)/
      layout.tsx                  # Marketing shell
      page.tsx                    # /
      pricing/page.tsx            # /pricing
    (auth)/
      login/page.tsx              # /login
      signup/page.tsx             # /signup
    (app)/
      layout.tsx                  # App shell; verifies session
      todos/
        page.tsx                  # /todos
        loading.tsx               # Skeleton while /todos streams
        error.tsx                 # Boundary for /todos subtree
        new/page.tsx              # /todos/new
        [todoId]/
          page.tsx                # /todos/:todoId
          not-found.tsx           # 404 for unknown todo
        @modal/                   # Parallel slot for intercepted detail
          default.tsx
          (.)[todoId]/page.tsx    # Intercepts /todos/:todoId from the list
    api/
      todos/route.ts              # GET/POST /api/todos
```

Route groups `(marketing)`, `(auth)`, and `(app)` give each area its own layout without changing URLs.

## Root Layout

```tsx
// src/app/layout.tsx
import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import { Providers } from './providers';

export const metadata: Metadata = {
  title: { default: 'Acme', template: '%s | Acme' },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
```

## Protected App Layout

```tsx
// src/app/(app)/layout.tsx
import { redirect } from 'next/navigation';
import type { ReactNode } from 'react';
import { getSession } from '@/lib/auth/getSession';
import { AppShell } from '@/features/app-shell/components/AppShell';

export default async function AppLayout({ children }: { children: ReactNode }) {
  const session = await getSession();
  if (!session) redirect('/login');
  return <AppShell user={session.user}>{children}</AppShell>;
}
```

`getSession` reads the cookie with `cookies()` from `next/headers` and verifies it. Layouts do not re-render on child navigation, so pages that need the user call `getSession()` themselves; it is wrapped in `cache()` so the verification runs once per request.

## Middleware Auth Redirect

```ts
// src/middleware.ts
import { NextResponse, type NextRequest } from 'next/server';

const PUBLIC_PATHS = ['/', '/pricing', '/login', '/signup', '/forgot-password'];

function isPublic(pathname: string): boolean {
  return PUBLIC_PATHS.some((path) => pathname === path || (path !== '/' && pathname.startsWith(`${path}/`)));
}

export function middleware(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  const hasSession = request.cookies.has('session');

  if (!hasSession && !isPublic(pathname)) {
    const loginUrl = new URL('/login', request.url);
    loginUrl.searchParams.set('redirectTo', pathname + search);
    return NextResponse.redirect(loginUrl);
  }

  if (hasSession && (pathname === '/login' || pathname === '/signup')) {
    return NextResponse.redirect(new URL('/todos', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)'],
};
```

| Rule                                                  | Reason                                            |
| ----------------------------------------------------- | ------------------------------------------------- |
| Check cookie presence only                            | Edge runtime; no database calls                   |
| Verify the session in layouts, pages, actions, routes | Middleware can be bypassed; it is an optimization |
| Exclude static assets in `matcher`                    | Avoid running on every image request              |
| Preserve `redirectTo` with the search string          | Deep links survive login                          |

Next.js 16 renames the file to `src/proxy.ts` and the export to `proxy`. Everything else is identical.

## Login Redirect Target

```ts
// src/features/auth/actions/loginAction.ts
'use server';

import { redirect } from 'next/navigation';
import { safeRedirect } from '@/lib/router/safeRedirect';

export async function loginAction(_previous: LoginActionState, formData: FormData): Promise<LoginActionState> {
  // ...validate and create the session cookie...
  redirect(safeRedirect(formData.get('redirectTo')?.toString() ?? null, '/todos'));
}
```

The login page reads `searchParams.redirectTo` and passes it into the form as a hidden input.

```ts
// src/lib/router/safeRedirect.ts
export function safeRedirect(value: string | null, fallback = '/'): string {
  if (!value || !value.startsWith('/') || value.startsWith('//') || value.includes('\\')) return fallback;
  return value;
}
```

Rejecting anything that does not start with a single `/` closes the open-redirect hole in `?redirectTo=`.

## Page with `loading`, `error`, and `not-found`

```tsx
// src/app/(app)/todos/page.tsx
import { z } from 'zod';
import { HydrationBoundary, dehydrate } from '@tanstack/react-query';
import { getQueryClient } from '@/app/getQueryClient';
import { todoRepository } from '@/lib/repositories';
import { todosQueryOptions } from '@/features/todos/api/useTodosQuery';
import { TodoListView } from '@/features/todos/components/TodoListView';

const searchParamsSchema = z.object({
  status: z.enum(['all', 'open', 'done']).catch('all'),
  page: z.coerce.number().int().min(1).catch(1),
});

interface PageProps {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

export default async function TodosPage({ searchParams }: PageProps) {
  const filters = searchParamsSchema.parse(await searchParams);
  const queryClient = getQueryClient();
  await queryClient.prefetchQuery(todosQueryOptions(todoRepository, filters));

  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      <TodoListView filters={filters} />
    </HydrationBoundary>
  );
}
```

```tsx
// src/app/(app)/todos/loading.tsx
import { TodoListSkeleton } from '@/features/todos/components/TodoListSkeleton';

export default function Loading() {
  return <TodoListSkeleton />;
}
```

```tsx
// src/app/(app)/todos/error.tsx
'use client';

export default function TodosError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <section role="alert">
      <h2>Could not load todos</h2>
      <p>{error.message}</p>
      <button type="button" onClick={reset}>Try again</button>
    </section>
  );
}
```

```tsx
// src/app/(app)/todos/[todoId]/not-found.tsx
import Link from 'next/link';
import { paths } from '@/app/paths';

export default function TodoNotFound() {
  return (
    <section>
      <h2>Todo not found</h2>
      <Link href={paths.todos()}>Back to todos</Link>
    </section>
  );
}
```

`error.tsx` catches errors from the page and its children, not from the layout in the same folder. A `global-error.tsx` at the root covers the root layout.

## Client Navigation

```tsx
// src/features/todos/components/TodoFilters.tsx
'use client';

import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { useTransition } from 'react';

const STATUSES = ['all', 'open', 'done'] as const;

export function TodoFilters({ status }: { status: (typeof STATUSES)[number] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [isPending, startTransition] = useTransition();

  const setStatus = (next: (typeof STATUSES)[number]) => {
    const params = new URLSearchParams(searchParams);
    if (next === 'all') params.delete('status');
    else params.set('status', next);
    params.delete('page');
    const query = params.toString();
    startTransition(() => {
      router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
    });
  };

  return (
    <div role="group" aria-label="Filter todos" aria-busy={isPending}>
      {STATUSES.map((value) => (
        <button key={value} type="button" aria-pressed={status === value} onClick={() => setStatus(value)}>
          {value}
        </button>
      ))}
    </div>
  );
}
```

`replace` for filter changes so the back button does not step through every filter; `push` for navigations to a new resource. Wrap any component that calls `useSearchParams` in a `Suspense` boundary or the whole page opts out of static rendering.

```tsx
// src/features/todos/components/TodoLink.tsx
import Link from 'next/link';
import { paths } from '@/app/paths';
import type { Todo } from '@acme/todo-repository';

export function TodoLink({ todo }: { todo: Todo }) {
  return <Link href={paths.todo(todo.id)} prefetch>{todo.title}</Link>;
}
```

## Typed Paths

```ts
// src/app/paths.ts
export const paths = {
  home: () => '/',
  login: (redirectTo?: string) =>
    redirectTo ? `/login?redirectTo=${encodeURIComponent(redirectTo)}` : '/login',
  todos: (status?: 'open' | 'done') => (status ? `/todos?status=${status}` : '/todos'),
  todoNew: () => '/todos/new',
  todo: (todoId: string) => `/todos/${encodeURIComponent(todoId)}`,
} as const;
```

With `typedRoutes: true` in `next.config.ts`, `Link href` is checked against the real route tree at build time. Keep `paths` regardless so components never build strings.

## Redirects and Rewrites

```ts
// next.config.ts
import type { NextConfig } from 'next';

const config: NextConfig = {
  typedRoutes: true,
  async redirects() {
    return [{ source: '/tasks/:id', destination: '/todos/:id', permanent: true }];
  },
};

export default config;
```

| Where                     | Use for                                           |
| ------------------------- | ------------------------------------------------- |
| `next.config.ts`          | Permanent URL renames                             |
| `middleware.ts`           | Auth, locale, A/B rewrites; needs request context |
| `redirect()` in a page    | Data-dependent redirect (deleted resource moved)  |
| `redirect()` in an action | After a successful mutation                       |

## Parallel and Intercepting Routes

| Convention           | Purpose                                                     |
| -------------------- | ----------------------------------------------------------- |
| `@modal/`            | A slot rendered by the parent layout alongside `children`   |
| `@modal/default.tsx` | Rendered when the slot has no match; return `null`          |
| `(.)[todoId]`        | Intercept a same-level route                                |
| `(..)segment`        | Intercept one level up; `(..)(..)` two levels; `(...)` root |

```tsx
// src/app/(app)/todos/layout.tsx
import type { ReactNode } from 'react';

export default function TodosLayout({ children, modal }: { children: ReactNode; modal: ReactNode }) {
  return (
    <>
      {children}
      {modal}
    </>
  );
}
```

```tsx
// src/app/(app)/todos/@modal/(.)[todoId]/page.tsx
import { todoRepository } from '@/lib/repositories';
import { TodoDetailModal } from '@/features/todos/components/TodoDetailModal';

export default async function InterceptedTodoPage({ params }: { params: Promise<{ todoId: string }> }) {
  const { todoId } = await params;
  const todo = await todoRepository.getTodo(todoId);
  if (!todo) return null;
  return <TodoDetailModal todo={todo} />;
}
```

Clicking a `Link` to `/todos/42` from the list renders the modal over the list. Refreshing `/todos/42` renders the full `[todoId]/page.tsx`. The modal's close button calls `router.back()`.
