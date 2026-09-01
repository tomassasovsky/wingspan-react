---
name: react-testing
description: Best practices for React unit, hook, component, and end-to-end tests using vitest, @testing-library/react, @testing-library/user-event, @testing-library/jest-dom, msw, and @playwright/test. Use when writing, modifying, or reviewing test files (*.test.ts, *.test.tsx, *.spec.ts), the renderWithProviders helper, msw handlers, vitest or Playwright configuration, or coverage thresholds.
argument-hint: "[file-or-directory]"
allowed-tools: Read Glob Grep Bash
---

# React Testing

Testing fundamentals for React projects: unit and hook tests with `vitest`, component tests through the accessible tree with `@testing-library/react`, network mocking with `msw`, and `@playwright/test` end-to-end tests for critical flows only.

---

## Core Standards

Apply these standards to ALL test work:

- **Test behavior through the accessible tree** — query with `getByRole` first, then `getByLabelText` and `getByText`; `getByTestId` is a last resort and requires a comment explaining why nothing else works
- **Use `userEvent.setup()`, never `fireEvent`** — `@testing-library/user-event` dispatches the full event sequence a real browser produces
- **Mock the network with `msw`, never `fetch` or the query hook** — tests exercise the real client, parser, and query hook end to end
- **Render through `renderWithProviders`** — one helper in `src/test/render.tsx` wraps `QueryClientProvider`, router, and theme; never inline providers in a test
- **Query from `screen`** — never destructure queries from the `render` result
- **Use `findBy*` for async UI** — never `waitFor` with an empty callback, `setTimeout`, or `act` sprinkled to silence warnings
- **One behavior per test** — each `it` asserts one observable outcome
- **`describe` blocks mirror the component or hook name** — `describe('LoginForm')`, `describe('useUserQuery')`
- **Colocate tests** — `Thing.tsx` sits beside `Thing.test.tsx`; `useThing.ts` beside `useThing.test.ts`
- **Mock only module boundaries** — `vi.mock` targets the data layer (repositories, clients, SDKs); never mock child components or internal hooks
- **Fake timers only when time matters** — `vi.useFakeTimers()` for debounce, polling, and timeouts; restore in `afterEach`
- **No snapshot tests for components** — snapshots are allowed only for serialized data (query keys, generated config, DTO mappings)
- **100% coverage thresholds in packages** — `coverage.thresholds` enforced in CI for every `packages/*` workspace
- **Zero `act()` warnings** — an `act` warning is a failing test; fix the missing `await` or `findBy*`
- **Playwright for critical flows only** — sign in, checkout, onboarding; everything else is a component test

---

## Test Structure

### File Organization

| Convention       | Rule                                                                                                     |
| ---------------- | -------------------------------------------------------------------------------------------------------- |
| **File suffix**  | Unit, hook, and component tests end with `.test.ts` or `.test.tsx`; Playwright specs end with `.spec.ts` |
| **Location**     | Colocated with the source file: `src/features/auth/components/LoginForm.test.tsx`                        |
| **E2E location** | `e2e/` at the app root with page objects in `e2e/pages/`                                                 |
| **Helpers**      | `src/test/` holds `render.tsx`, `setup.ts`, `server.ts`, `handlers.ts`, and `factories.ts`               |

### Naming Conventions

Test names read as `<verb> <outcome> when <condition>`.

| Pattern            | Example                                            |
| ------------------ | -------------------------------------------------- |
| **Renders**        | `renders empty state when list has no items`       |
| **Calls callback** | `calls onSubmit with payload when form is valid`   |
| **Async outcome**  | `shows users after the request resolves`           |
| **Error path**     | `shows error alert when request fails with 500`    |
| **Conditional**    | `disables submit button while mutation is pending` |
| **Navigation**     | `navigates to /dashboard when sign in succeeds`    |
| **Hook result**    | `returns debounced value after delay elapses`      |
| **Accessibility**  | `moves focus to dialog when opened`                |

### Query Priority

| Priority | Query                  | Use for                                                          |
| -------- | ---------------------- | ---------------------------------------------------------------- |
| 1        | `getByRole`            | Buttons, links, headings, textboxes, checkboxes, dialogs, alerts |
| 2        | `getByLabelText`       | Form controls without a textbox role (password, file, date)      |
| 3        | `getByText`            | Non-interactive content: paragraphs, cells, list items           |
| 4        | `getByDisplayValue`    | Current value of an input                                        |
| 5        | `getByAltText`         | Images                                                           |
| 6        | `getByPlaceholderText` | Only when no label exists; file an accessibility bug             |
| Last     | `getByTestId`          | Nothing else works; add a comment explaining why                 |

| Variant    | Returns            | Use when                                               |
| ---------- | ------------------ | ------------------------------------------------------ |
| `getBy*`   | Element or throws  | Element must be present now                            |
| `queryBy*` | Element or `null`  | Asserting absence with `not.toBeInTheDocument()`       |
| `findBy*`  | `Promise<Element>` | Element appears after async work (network, transition) |

---

## `renderWithProviders`

```tsx
// src/test/render.tsx
import type { ReactElement, ReactNode } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, type RenderOptions } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router';

import { ThemeProvider } from '@/app/providers/ThemeProvider';

interface WrapperOptions {
  route?: string;
  queryClient?: QueryClient;
}

type RenderWithProvidersOptions = WrapperOptions & Omit<RenderOptions, 'wrapper'>;

export function createTestQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: Infinity, staleTime: 0 },
      mutations: { retry: false },
    },
  });
}

export function createWrapper({ route = '/', queryClient = createTestQueryClient() }: WrapperOptions = {}) {
  return function Wrapper({ children }: { children: ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[route]}>
          <ThemeProvider>{children}</ThemeProvider>
        </MemoryRouter>
      </QueryClientProvider>
    );
  };
}

export function renderWithProviders(
  ui: ReactElement,
  { route, queryClient = createTestQueryClient(), ...options }: RenderWithProvidersOptions = {},
) {
  const user = userEvent.setup();
  return {
    user,
    queryClient,
    ...render(ui, { wrapper: createWrapper({ route, queryClient }), ...options }),
  };
}
```

---

## Component Test

```tsx
// src/features/auth/components/LoginForm.test.tsx
import { screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { renderWithProviders } from '@/test/render';

import { LoginForm } from './LoginForm';

describe('LoginForm', () => {
  it('calls onSubmit with credentials when form is valid', async () => {
    const onSubmit = vi.fn();
    const { user } = renderWithProviders(<LoginForm onSubmit={onSubmit} />);

    await user.type(screen.getByRole('textbox', { name: /email/i }), 'dash@example.com');
    await user.type(screen.getByLabelText(/password/i), 'hunter22');
    await user.click(screen.getByRole('button', { name: /sign in/i }));

    await waitFor(() => {
      expect(onSubmit).toHaveBeenCalledWith({ email: 'dash@example.com', password: 'hunter22' });
    });
  });

  it('shows validation error and does not submit when email is empty', async () => {
    const onSubmit = vi.fn();
    const { user } = renderWithProviders(<LoginForm onSubmit={onSubmit} />);

    await user.click(screen.getByRole('button', { name: /sign in/i }));

    expect(await screen.findByRole('alert')).toHaveTextContent(/email is required/i);
    expect(onSubmit).not.toHaveBeenCalled();
  });
});
```

`waitFor` is correct here because the assertion is on a spy, not the DOM; the callback always contains an assertion. Password inputs have no textbox role, so `getByLabelText` is the right query.

---

## Hook Test

```ts
// src/features/users/api/useUserQuery.test.ts
import { renderHook, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { ApiError } from '@acme/api-client';
import { createWrapper } from '@/test/render';
import { server } from '@/test/server';

import { useUserQuery } from './useUserQuery';

describe('useUserQuery', () => {
  it('returns the user when the request succeeds', async () => {
    const { result } = renderHook(() => useUserQuery('1'), { wrapper: createWrapper() });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(result.current.data).toEqual({ id: '1', name: 'Dash', email: 'dash@example.com' });
  });

  it('returns ApiError when the API responds with 404', async () => {
    server.use(
      http.get('/api/users/:id', () => HttpResponse.json({ message: 'Not found' }, { status: 404 })),
    );

    const { result } = renderHook(() => useUserQuery('missing'), { wrapper: createWrapper() });

    await waitFor(() => expect(result.current.isError).toBe(true));

    expect(result.current.error).toBeInstanceOf(ApiError);
  });
});
```

---

## Network Mocking with `msw`

```ts
// src/test/handlers.ts
import { http, HttpResponse } from 'msw';

import type { UserDto } from '@acme/api-client';

export const users: readonly UserDto[] = [
  { id: '1', name: 'Dash', email: 'dash@example.com' },
  { id: '2', name: 'Sparky', email: 'sparky@example.com' },
];

export const handlers = [
  http.get('/api/users', () => HttpResponse.json(users)),
  http.get('/api/users/:id', ({ params }) => {
    const user = users.find((candidate) => candidate.id === params['id']);
    return user
      ? HttpResponse.json(user)
      : HttpResponse.json({ message: 'Not found' }, { status: 404 });
  }),
];
```

```ts
// src/test/server.ts
import { setupServer } from 'msw/node';

import { handlers } from './handlers';

export const server = setupServer(...handlers);
```

```ts
// src/test/setup.ts
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

`onUnhandledRequest: 'error'` turns every unmocked request into a test failure. Override per test with `server.use(...)`; `resetHandlers` in `afterEach` removes overrides. Module-boundary mocks with `vi.mock` and fake timers are covered in [references/component-tests.md](references/component-tests.md).

---

## End-to-End with Playwright

```ts
// e2e/pages/login.page.ts
import type { Locator, Page } from '@playwright/test';

export class LoginPage {
  readonly email: Locator;
  readonly password: Locator;
  readonly submit: Locator;
  readonly error: Locator;

  constructor(private readonly page: Page) {
    this.email = page.getByRole('textbox', { name: /email/i });
    this.password = page.getByLabel(/password/i);
    this.submit = page.getByRole('button', { name: /sign in/i });
    this.error = page.getByRole('alert');
  }

  async goto(): Promise<void> {
    await this.page.goto('/login');
  }

  async signIn(email: string, password: string): Promise<void> {
    await this.email.fill(email);
    await this.password.fill(password);
    await this.submit.click();
  }
}
```

```ts
// e2e/login.spec.ts
import { expect, test } from '@playwright/test';

import { LoginPage } from './pages/login.page';

test.describe('Login', () => {
  test('redirects to dashboard when credentials are valid', async ({ page }) => {
    const login = new LoginPage(page);
    await login.goto();

    await login.signIn('dash@example.com', 'hunter22');

    await expect(page).toHaveURL(/\/dashboard$/);
    await expect(page.getByRole('heading', { name: /welcome, dash/i })).toBeVisible();
  });

  test('shows an error when credentials are invalid', async ({ page }) => {
    const login = new LoginPage(page);
    await login.goto();

    await login.signIn('dash@example.com', 'wrong');

    await expect(login.error).toHaveText(/invalid email or password/i);
  });
});
```

Page objects expose locators and intents, never assertions. Every locator uses the same role-first priority as component tests.

---

## Anti-Patterns

| Anti-Pattern                                   | Problem                                                      | Correct Approach                                             |
| ---------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| `fireEvent.click(button)`                      | Skips pointer, focus, and keyboard events real users trigger | `await user.click(button)` from `userEvent.setup()`          |
| `getByTestId` as the default query             | Couples tests to markup; hides accessibility gaps            | `getByRole` with an accessible name                          |
| `vi.spyOn(globalThis, 'fetch')`                | Bypasses the client and parser; drifts from production       | `msw` handlers in `src/test/handlers.ts`                     |
| `vi.mock('./useUsersQuery')`                   | Tests the mock, not the feature                              | Render with the real hook; mock the network with `msw`       |
| `await waitFor(() => {})`                      | Waits for nothing; hides race conditions                     | `await screen.findByRole(...)`                               |
| `await new Promise((r) => setTimeout(r, 100))` | Flaky and slow                                               | `findBy*` or `vi.useFakeTimers()` with `advanceTimersByTime` |
| `expect(container).toMatchSnapshot()`          | Asserts nothing meaningful; rubber-stamped on every change   | Assert visible text, roles, and callbacks                    |
| Inline `<QueryClientProvider>` in each test    | Duplicated setup; inconsistent client options                | `renderWithProviders`                                        |
| `const { getByText } = render(...)`            | Diverges from `screen`; breaks with portals                  | `screen.getByText(...)`                                      |
| Multiple unrelated assertions in one `it`      | First failure hides the rest; unclear name                   | One behavior per test                                        |
| Playwright spec for every component state      | Slow suite; duplicates component tests                       | Component tests for states; Playwright for critical flows    |
| Ignoring `act()` warnings                      | Assertions run against stale UI                              | `await` the interaction or use `findBy*`                     |

---

## Additional Resources

- [references/configuration.md](references/configuration.md) — complete `vitest.config.ts` (jsdom/happy-dom, v8 coverage thresholds, setup files, monorepo projects), `playwright.config.ts`, and CI commands
- [references/component-tests.md](references/component-tests.md) — async UI, forms, lists, portals and dialogs, keyboard interaction, error boundaries, Suspense, data routes, module-boundary mocks, and fake timers
- [references/msw.md](references/msw.md) — handler organization, per-test overrides with `server.use`, error and latency cases, typed handlers with `zod`
- [references/matchers.md](references/matchers.md) — `@testing-library/jest-dom` matchers with when to use each
- [references/coverage.md](references/coverage.md) — measuring coverage, thresholds, ignoring generated files, and the gaps that matter
