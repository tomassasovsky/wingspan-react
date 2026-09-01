---
name: react-routing
description: Best practices for routing in React applications using React Router v7 in data mode for Vite apps or the Next.js App Router for Next.js apps. Use when creating, modifying, or reviewing routes, layouts, loaders, actions, protected routes, redirects, deep links, search params, middleware, or navigation code that uses react-router, next/navigation, or the app directory.
allowed-tools: Read Glob Grep
---

# Routing

Routing for React applications in two lanes: React Router v7 data mode for Vite SPAs, and the Next.js App Router for server-rendered apps. Every route is a URL a user can bookmark, share, and refresh.

---

## Core Standards

Apply these standards to ALL routing work:

- **Detect the lane from `package.json` and follow it** — `next` means App Router; `react-router` means data mode; never mix
- **Every screen has a URL** — modals, tabs, wizard steps, and filters that a user would share live in the path or search params
- **Load data in loaders or server components** — never `useEffect` fetches in route components
- **Redirects happen before render** — loader `redirect()` or `middleware.ts`; never a `useEffect` that calls `navigate`
- **Route params are parsed with `zod`** — never trust `params` or `searchParams` as typed
- **Route paths come from one typed helper** — never string-concatenate paths in components
- **Lazy-load route modules** — `lazy` in React Router; automatic per-route in Next.js
- **Every route has an error boundary** — `ErrorBoundary` export or `error.tsx`
- **Hyphenated lowercase segments** — `/order-history/:orderId`, never `/orderHistory`
- **Path params identify resources; search params filter them** — `/todos/:todoId` and `/todos?status=done`
- **Page/View split** — the route component wires data and params; a `View` renders from props and is tested without a router
- **Every route ships with a test** — memory router or mocked `next/navigation`, plus a Playwright flow for critical paths

---

## Lane Detection

| `package.json` has         | Lane                      | Router entry                             |
| -------------------------- | ------------------------- | ---------------------------------------- |
| `next`                     | Next.js App Router        | `src/app/**/page.tsx`                    |
| `react-router` (no `next`) | React Router v7 data mode | `src/app/router.tsx`                     |
| `@react-router/dev`        | React Router framework    | `app/routes.ts`; same loader rules apply |

---

## Lane A: React Router v7 (Data Mode)

### Router

```tsx
// src/app/router.tsx
import { createBrowserRouter } from 'react-router';
import { RootLayout } from './RootLayout';
import { RootErrorBoundary } from './RootErrorBoundary';

export const router = createBrowserRouter([
  {
    path: '/',
    Component: RootLayout,
    ErrorBoundary: RootErrorBoundary,
    children: [
      { index: true, lazy: () => import('@/features/home/routes/home') },
      { path: 'login', lazy: () => import('@/features/auth/routes/login') },
      {
        path: 'todos',
        lazy: () => import('@/features/todos/routes/todosLayout'),
        children: [
          { index: true, lazy: () => import('@/features/todos/routes/todoList') },
          { path: ':todoId', lazy: () => import('@/features/todos/routes/todoDetail') },
        ],
      },
      { path: '*', lazy: () => import('@/features/not-found/routes/notFound') },
    ],
  },
]);
```

`main.tsx` renders `<RouterProvider router={router} />` inside the app providers. Export the route array separately so tests can build a memory router from the same tree.

### Route Module with Loader, Action, and Error Boundary

```tsx
// src/features/todos/routes/todoDetail.tsx
import { data, redirect, useLoaderData, type ActionFunctionArgs, type LoaderFunctionArgs } from 'react-router';
import { z } from 'zod';
import { queryClient } from '@/app/queryClient';
import { todoRepository } from '@/lib/repositories';
import { requireUser } from '@/features/auth/lib/requireUser';
import { todoQueryOptions } from '../api/useTodoQuery';
import { todoKeys } from '../api/todoKeys';
import { TodoDetailView } from '../components/TodoDetailView';
import { RouteError } from '@/components/RouteError';

const paramsSchema = z.object({ todoId: z.string().min(1) });

export async function loader({ params, request }: LoaderFunctionArgs) {
  await requireUser(request);
  const { todoId } = paramsSchema.parse(params);
  const todo = await queryClient.ensureQueryData(todoQueryOptions(todoRepository, todoId));
  if (!todo) throw data({ message: 'Todo not found' }, { status: 404 });
  return { todoId };
}

export async function action({ params, request }: ActionFunctionArgs) {
  await requireUser(request);
  const { todoId } = paramsSchema.parse(params);
  const form = await request.formData();
  if (form.get('intent') === 'delete') {
    await todoRepository.deleteTodo(todoId);
    await queryClient.invalidateQueries({ queryKey: todoKeys.lists() });
    return redirect('/todos');
  }
  throw data({ message: 'Unknown intent' }, { status: 400 });
}

export function Component() {
  const { todoId } = useLoaderData<typeof loader>();
  return <TodoDetailView todoId={todoId} />;
}

export const ErrorBoundary = RouteError;
```

The loader returns only the parsed id; the view reads the todo with `useSuspenseQuery`, so the cache stays the single source of truth.

### Protected Routes

```ts
// src/features/auth/lib/requireUser.ts
import { redirect } from 'react-router';
import { queryClient } from '@/app/queryClient';
import { sessionQueryOptions } from '../api/useSessionQuery';
import type { User } from '@acme/auth-repository';

export async function requireUser(request: Request): Promise<User> {
  const user = await queryClient.ensureQueryData(sessionQueryOptions());
  if (user) return user;
  const url = new URL(request.url);
  const redirectTo = encodeURIComponent(url.pathname + url.search);
  throw redirect(`/login?redirectTo=${redirectTo}`);
}
```

Call `requireUser` in every protected loader and action. Parent and child loaders run in parallel, so a layout loader alone does not guard its children.

### Typed Params and Paths

```ts
// src/lib/router/useTypedParams.ts
import { useParams } from 'react-router';
import type { z } from 'zod';

export function useTypedParams<Schema extends z.ZodType>(schema: Schema): z.output<Schema> {
  return schema.parse(useParams());
}
```

Paths come from one `paths` object (`paths.todo(id)`) that encodes ids and search params; components never build strings.

### URL State with `useSearchParams`

```ts
const filtersSchema = z.object({
  status: z.enum(['all', 'open', 'done']).catch('all'),
  page: z.coerce.number().int().min(1).catch(1),
});

const [searchParams, setSearchParams] = useSearchParams();
const filters = filtersSchema.parse(Object.fromEntries(searchParams));
```

`catch` gives every invalid or missing param a default instead of throwing. Wrap reads and writes in a `use<Feature>Filters` hook that omits default values from the URL so `/todos` stays canonical.

See [references/react-router.md](references/react-router.md) for the complete router with nested layouts, the layout route module, `Form`/`useFetcher` actions, the full `paths` helper, and the `useTodoFilters` hook.

---

## Lane B: Next.js App Router

### File Conventions

| File                | Role                                                 | Server or client       |
| ------------------- | ---------------------------------------------------- | ---------------------- |
| `layout.tsx`        | Shared shell; persists across child navigations      | Server by default      |
| `page.tsx`          | The route's UI; receives `params` and `searchParams` | Server by default      |
| `loading.tsx`       | Suspense fallback for the segment                    | Server                 |
| `error.tsx`         | Error boundary with `reset()`                        | Must be `'use client'` |
| `not-found.tsx`     | Rendered by `notFound()`                             | Server                 |
| `route.ts`          | HTTP handler (`GET`, `POST`)                         | Server                 |
| `(group)/`          | Route group; organizes without affecting the URL     |                        |
| `[segment]/`        | Dynamic segment; `[...slug]` catch-all               |                        |
| `@slot/`            | Parallel route slot                                  |                        |
| `(.)segment/`       | Intercepting route                                   |                        |
| `src/middleware.ts` | Runs before matching; auth redirects, rewrites       | Edge runtime           |

### Dynamic Page with Typed Params and Search Params

```tsx
// src/app/(app)/todos/[todoId]/page.tsx
import { notFound } from 'next/navigation';
import { z } from 'zod';
import { todoRepository } from '@/lib/repositories';
import { TodoDetailView } from '@/features/todos/components/TodoDetailView';

const paramsSchema = z.object({ todoId: z.string().min(1) });
const searchParamsSchema = z.object({ tab: z.enum(['details', 'activity']).catch('details') });

interface PageProps {
  params: Promise<{ todoId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

export default async function TodoPage({ params, searchParams }: PageProps) {
  const { todoId } = paramsSchema.parse(await params);
  const { tab } = searchParamsSchema.parse(await searchParams);
  const todo = await todoRepository.getTodo(todoId);
  if (!todo) notFound();
  return <TodoDetailView todo={todo} tab={tab} />;
}

export async function generateStaticParams() {
  const todos = await todoRepository.getTodos({});
  return todos.map((todo) => ({ todoId: todo.id }));
}
```

`params` and `searchParams` are promises; always `await` them. Next.js 15.5+ also generates `PageProps<'/todos/[todoId]'>`; use it in place of the local interface when available.

### Auth Redirect in Middleware

```ts
// src/middleware.ts
import { NextResponse, type NextRequest } from 'next/server';

const PUBLIC_PATHS = ['/login', '/signup', '/forgot-password'];

export function middleware(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  const hasSession = request.cookies.has('session');
  const isPublic = PUBLIC_PATHS.some((path) => pathname === path || pathname.startsWith(`${path}/`));

  if (!hasSession && !isPublic) {
    const loginUrl = new URL('/login', request.url);
    loginUrl.searchParams.set('redirectTo', pathname + search);
    return NextResponse.redirect(loginUrl);
  }
  if (hasSession && isPublic) {
    return NextResponse.redirect(new URL('/', request.url));
  }
  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|ico)$).*)'],
};
```

Middleware checks cookie presence for fast redirects only. Every server component, route handler, and server action verifies the session itself; never treat middleware as the sole gate. Next.js 16 renames this file to `proxy.ts` with an exported `proxy` function; the body is unchanged.

### Navigation

| Need                         | Use                                                       |
| ---------------------------- | --------------------------------------------------------- |
| Link in JSX                  | `<Link href={paths.todo(id)}>`                            |
| Navigate after an action     | `redirect()` from `next/navigation` inside the action     |
| Navigate from a client event | `const router = useRouter(); router.push(paths.todo(id))` |
| Refresh server data          | `router.refresh()` or `revalidatePath()` in the action    |
| Read the path on the client  | `usePathname()`                                           |
| Read search params (client)  | `useSearchParams()`; wrap the component in `Suspense`     |
| Read search params (server)  | `searchParams` prop on `page.tsx`                         |
| 404                          | `notFound()`                                              |

See [references/nextjs.md](references/nextjs.md) for the complete app tree with `layout`/`loading`/`error`/`not-found`, the client navigation component, a search-param filter that updates the URL, and parallel and intercepting routes.

---

## Deep Linking and Redirects

| Rule                                       | React Router                                      | Next.js                                |
| ------------------------------------------ | ------------------------------------------------- | -------------------------------------- |
| Preserve the destination on login redirect | `?redirectTo=` from `requireUser`                 | `?redirectTo=` from `middleware.ts`    |
| Validate `redirectTo` before following it  | Same-origin path only; reject `//` and `http`     | Same                                   |
| Unknown resource                           | `throw data(..., { status: 404 })`                | `notFound()`                           |
| Renamed path                               | `{ path: 'old', loader: () => redirect('/new') }` | `redirects()` in `next.config.ts`      |
| Modal from a list item                     | Child route under the list route                  | Intercepting route `(.)todos/[todoId]` |
| Wizard step                                | `/onboarding/:step`                               | `/onboarding/[step]`                   |

`safeRedirect(value, fallback)` accepts only paths that start with a single `/`; both references include it.

---

## Anti-Patterns

| Anti-Pattern                                         | Problem                                       | Correct Approach                                      |
| ---------------------------------------------------- | --------------------------------------------- | ----------------------------------------------------- |
| `useEffect(() => { if (!user) navigate('/login') })` | Flash of protected content; runs after render | Loader `redirect()` or `middleware.ts`                |
| `useEffect` fetch in a route component               | Waterfalls, no prefetch, no cancellation      | Loader + `ensureQueryData`, or server component       |
| `` navigate(`/todos/${id}`) `` string literals       | Typos, unencoded ids                          | `paths.todo(id)`                                      |
| `params.todoId!` or `as string`                      | Runtime `undefined` in production             | `paramsSchema.parse(params)`                          |
| Filter state in `useState`                           | Not shareable, lost on refresh                | `useSearchParams` / `searchParams` prop               |
| `<a href="/todos">`                                  | Full page reload                              | `<Link>`                                              |
| Following `?redirectTo=https://evil.example`         | Open redirect                                 | `safeRedirect()`                                      |
| `'use client'` on `page.tsx` to read params          | Loses server rendering                        | `await params` in the server page; pass down as props |
| `middleware.ts` as the only auth check               | Bypassable                                    | Verify the session in every server entry point        |
| Static `import` of every route component             | One large bundle                              | `lazy` per route                                      |
| `errorElement` missing on the root                   | White screen on any thrown error              | `ErrorBoundary` on root and per feature               |

---

## References

- [references/react-router.md](references/react-router.md) — complete data-mode router, nested layouts, route module pattern, `Form` and `useFetcher` actions, typed route helpers
- [references/nextjs.md](references/nextjs.md) — complete App Router example with `middleware.ts` auth redirect, client navigation, search-param filters, parallel and intercepting routes
- [references/testing.md](references/testing.md) — `createMemoryRouter` + `RouterProvider` tests, mocking `next/navigation` with `vi.mock`, Playwright navigation flows
