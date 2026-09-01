# Testing Routes

Stack: `vitest`, `@testing-library/react`, `@testing-library/user-event`, `msw`, `@playwright/test`. Component tests render real routers in memory; Playwright covers the flows that cross pages.

## React Router: `createMemoryRouter` + `RouterProvider`

Build a memory router from the production `routes` array so tests exercise real loaders, actions, and error boundaries.

```tsx
// src/test/renderRoute.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@testing-library/react';
import { RouterProvider, createMemoryRouter, type RouteObject } from 'react-router';
import { routes } from '@/app/router';

interface RenderRouteOptions {
  path: string;
  routeTree?: RouteObject[];
}

export function renderRoute({ path, routeTree = routes }: RenderRouteOptions) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(routeTree, { initialEntries: [path] });
  const utils = render(
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>,
  );
  return { ...utils, router, queryClient };
}
```

When loaders import a module-level `queryClient`, clear it in `beforeEach` with `queryClient.clear()` so tests do not share cache.

```tsx
// src/features/todos/routes/todoDetail.test.tsx
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { beforeEach, describe, expect, it } from 'vitest';
import { queryClient } from '@/app/queryClient';
import { renderRoute } from '@/test/renderRoute';
import { server } from '@/test/server';

describe('todo detail route', () => {
  beforeEach(() => {
    queryClient.clear();
    server.use(http.get('/api/session', () => HttpResponse.json({ id: 'u1', name: 'Ada' })));
  });

  it('renders the todo from the loader', async () => {
    renderRoute({ path: '/todos/1' });
    expect(await screen.findByRole('heading', { name: 'Write tests' })).toBeInTheDocument();
  });

  it('renders the 404 boundary for an unknown todo', async () => {
    server.use(http.get('/api/todos/missing', () => HttpResponse.json({}, { status: 404 })));
    renderRoute({ path: '/todos/missing' });
    expect(await screen.findByRole('alert')).toHaveTextContent('Todo not found');
  });

  it('redirects to login with redirectTo when signed out', async () => {
    server.use(http.get('/api/session', () => HttpResponse.json(null, { status: 401 })));
    const { router } = renderRoute({ path: '/todos/1' });
    await screen.findByRole('heading', { name: 'Sign in' });
    expect(router.state.location.pathname).toBe('/login');
    expect(router.state.location.search).toBe('?redirectTo=%2Ftodos%2F1');
  });

  it('deletes and navigates back to the list', async () => {
    const user = userEvent.setup();
    const { router } = renderRoute({ path: '/todos/1' });
    await screen.findByRole('heading', { name: 'Write tests' });

    await user.click(screen.getByRole('button', { name: 'Delete' }));

    await screen.findByRole('heading', { name: 'Todos' });
    expect(router.state.location.pathname).toBe('/todos');
  });
});
```

`router.state.location` is the assertion point for navigation; never assert on `window.location` in a memory router.

### Testing a View Without a Router

Views render from props and never call router hooks. Test them with plain `render`.

```tsx
render(<TodoDetailView todo={todo} onDelete={vi.fn()} />);
```

### Testing a Component That Uses `Link` or `useNavigate`

Give it a minimal route tree instead of mocking `react-router`.

```tsx
// src/features/todos/components/TodoLink.test.tsx
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { renderRoute } from '@/test/renderRoute';
import { TodoLink } from './TodoLink';

describe('TodoLink', () => {
  it('navigates to the todo', async () => {
    const user = userEvent.setup();
    const { router } = renderRoute({
      path: '/',
      routeTree: [
        { path: '/', element: <TodoLink todo={{ id: 'a/b', title: 'Slashes', completed: false }} /> },
        { path: '/todos/:todoId', element: <p>Detail</p> },
      ],
    });

    await user.click(screen.getByRole('link', { name: 'Slashes' }));

    expect(await screen.findByText('Detail')).toBeInTheDocument();
    expect(router.state.location.pathname).toBe('/todos/a%2Fb');
  });
});
```

### Testing `useSearchParams` Hooks

```tsx
// src/features/todos/hooks/useTodoFilters.test.tsx
import { renderHook, act } from '@testing-library/react';
import { RouterProvider, createMemoryRouter } from 'react-router';
import type { ReactNode } from 'react';
import { describe, expect, it } from 'vitest';
import { useTodoFilters } from './useTodoFilters';

function createWrapper(initialPath: string) {
  return function Wrapper({ children }: { children: ReactNode }) {
    const router = createMemoryRouter([{ path: '/todos', element: children }], { initialEntries: [initialPath] });
    return <RouterProvider router={router} />;
  };
}

describe('useTodoFilters', () => {
  it('parses params with defaults', () => {
    const { result } = renderHook(() => useTodoFilters(), { wrapper: createWrapper('/todos?status=done&page=x') });
    expect(result.current.filters).toEqual({ status: 'done', page: 1 });
  });

  it('writes non-default values only', () => {
    const { result } = renderHook(() => useTodoFilters(), { wrapper: createWrapper('/todos?status=done') });
    act(() => result.current.setFilters({ status: 'all', page: 3 }));
    expect(result.current.filters).toEqual({ status: 'all', page: 3 });
  });
});
```

## Next.js: Mocking `next/navigation`

Pages are server components; client components use `next/navigation` hooks. Mock the module once in a shared helper and assert on the router mock.

```ts
// src/test/mockNextNavigation.ts
import { vi } from 'vitest';

export const routerMock = {
  push: vi.fn(),
  replace: vi.fn(),
  back: vi.fn(),
  forward: vi.fn(),
  refresh: vi.fn(),
  prefetch: vi.fn(),
};

export const navigationState = {
  pathname: '/',
  searchParams: new URLSearchParams(),
};

vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => navigationState.pathname,
  useSearchParams: () => navigationState.searchParams,
  useParams: () => ({}),
  redirect: vi.fn((url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`);
  }),
  notFound: vi.fn(() => {
    throw new Error('NEXT_NOT_FOUND');
  }),
}));
```

Import `@/test/mockNextNavigation` at the top of any test that needs it; `vi.mock` is hoisted per file.

```tsx
// src/features/todos/components/TodoFilters.test.tsx
import '@/test/mockNextNavigation';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { navigationState, routerMock } from '@/test/mockNextNavigation';
import { TodoFilters } from './TodoFilters';

describe('TodoFilters', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    navigationState.pathname = '/todos';
    navigationState.searchParams = new URLSearchParams('status=open&page=2');
  });

  it('replaces the URL with the new status and resets the page', async () => {
    const user = userEvent.setup();
    render(<TodoFilters status="open" />);

    await user.click(screen.getByRole('button', { name: 'done' }));

    expect(routerMock.replace).toHaveBeenCalledWith('/todos?status=done', { scroll: false });
  });

  it('removes the status param for all', async () => {
    const user = userEvent.setup();
    render(<TodoFilters status="open" />);

    await user.click(screen.getByRole('button', { name: 'all' }));

    expect(routerMock.replace).toHaveBeenCalledWith('/todos', { scroll: false });
  });
});
```

### Testing an Async Server Page

Call the page as a function with promise props and render the result.

```tsx
// src/app/(app)/todos/[todoId]/page.test.tsx
import '@/test/mockNextNavigation';
import { render, screen } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';
import { server } from '@/test/server';
import TodoPage from './page';

describe('TodoPage', () => {
  it('renders the todo', async () => {
    const page = await TodoPage({
      params: Promise.resolve({ todoId: '1' }),
      searchParams: Promise.resolve({ tab: 'activity' }),
    });
    render(page);
    expect(screen.getByRole('heading', { name: 'Write tests' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'Activity' })).toHaveAttribute('aria-selected', 'true');
  });

  it('calls notFound for an unknown todo', async () => {
    server.use(http.get('/api/todos/missing', () => HttpResponse.json({}, { status: 404 })));
    await expect(
      TodoPage({ params: Promise.resolve({ todoId: 'missing' }), searchParams: Promise.resolve({}) }),
    ).rejects.toThrow('NEXT_NOT_FOUND');
  });
});
```

Pages that render other async server components cannot be rendered this way; cover those with Playwright.

### Testing `middleware.ts`

```ts
// src/middleware.test.ts
import { NextRequest } from 'next/server';
import { describe, expect, it } from 'vitest';
import { middleware } from './middleware';

function request(path: string, cookie?: string) {
  const req = new NextRequest(new URL(path, 'http://localhost'));
  if (cookie) req.cookies.set('session', cookie);
  return req;
}

describe('middleware', () => {
  it('redirects signed-out users to login with redirectTo', () => {
    const response = middleware(request('/todos?status=done'));
    expect(response.status).toBe(307);
    expect(response.headers.get('location')).toBe('http://localhost/login?redirectTo=%2Ftodos%3Fstatus%3Ddone');
  });

  it('lets signed-out users reach public paths', () => {
    expect(middleware(request('/pricing')).status).toBe(200);
  });

  it('sends signed-in users away from login', () => {
    const response = middleware(request('/login', 'abc'));
    expect(response.headers.get('location')).toBe('http://localhost/todos');
  });
});
```

## Playwright: Navigation Flows

```ts
// e2e/todos.spec.ts
import { expect, test } from '@playwright/test';

test.describe('todos navigation', () => {
  test('redirects to login and back to the deep link', async ({ page }) => {
    await page.goto('/todos/1');
    await expect(page).toHaveURL(/\/login\?redirectTo=%2Ftodos%2F1$/);

    await page.getByLabel('Email').fill('ada@example.com');
    await page.getByLabel('Password').fill('correct-horse');
    await page.getByRole('button', { name: 'Sign in' }).click();

    await expect(page).toHaveURL(/\/todos\/1$/);
    await expect(page.getByRole('heading', { name: 'Write tests' })).toBeVisible();
  });

  test('filters are reflected in the URL and survive reload', async ({ page }) => {
    await page.goto('/todos');
    await page.getByRole('button', { name: 'done' }).click();
    await expect(page).toHaveURL(/\/todos\?status=done$/);

    await page.reload();
    await expect(page.getByRole('button', { name: 'done' })).toHaveAttribute('aria-pressed', 'true');
  });

  test('opens a todo, deletes it, and returns to the list', async ({ page }) => {
    await page.goto('/todos');
    await page.getByRole('link', { name: 'Write tests' }).click();
    await expect(page).toHaveURL(/\/todos\/1$/);

    await page.getByRole('button', { name: 'Delete' }).click();
    await expect(page).toHaveURL(/\/todos$/);
    await expect(page.getByRole('link', { name: 'Write tests' })).toHaveCount(0);
  });

  test('unknown routes render the not-found page', async ({ page }) => {
    const response = await page.goto('/does-not-exist');
    expect(response?.status()).toBe(404);
    await expect(page.getByRole('heading', { name: 'Page not found' })).toBeVisible();
  });
});
```

Use `storageState` in `playwright.config.ts` for tests that start signed in, so only the login flow test performs the login.

## Anti-Patterns in Route Tests

| Anti-Pattern                                    | Problem                                             | Correct Approach                        |
| ----------------------------------------------- | --------------------------------------------------- | --------------------------------------- |
| `vi.mock('react-router')`                       | Tests a fake router; loaders and redirects untested | `createMemoryRouter` with real routes   |
| Wrapping in `<MemoryRouter>` for data routes    | Loaders and actions never run                       | `createMemoryRouter` + `RouterProvider` |
| Asserting `window.location`                     | Memory routers do not touch it                      | `router.state.location`                 |
| Rendering `page.tsx` with `render(<Page />)`    | Async components return promises                    | `render(await Page(props))`             |
| Forgetting `vi.clearAllMocks()` on `routerMock` | Assertions see calls from earlier tests             | `beforeEach(() => vi.clearAllMocks())`  |
| Logging in through the UI in every e2e test     | Slow, flaky                                         | `storageState`                          |
