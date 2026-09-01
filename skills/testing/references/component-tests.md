# Component Test Patterns

Every example renders through `renderWithProviders` from `src/test/render.tsx`, queries from `screen`, and interacts through the returned `user`.

## Async UI

Components backed by `@tanstack/react-query` go through loading, success, and error states. Assert each state with `findBy*`; never assert on `isLoading` flags.

```tsx
// src/features/users/components/UserList.tsx
import { useUsersQuery } from '../api/useUsersQuery';

export function UserList() {
  const { data, isPending, isError, refetch } = useUsersQuery();

  if (isPending) return <p role="status">Loading users</p>;
  if (isError) {
    return (
      <div role="alert">
        <p>Could not load users</p>
        <button type="button" onClick={() => void refetch()}>Retry</button>
      </div>
    );
  }
  if (data.length === 0) return <p>No users yet</p>;

  return (
    <ul aria-label="Users">
      {data.map((user) => (
        <li key={user.id}>{user.name}</li>
      ))}
    </ul>
  );
}
```

```tsx
// src/features/users/components/UserList.test.tsx
import { screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { renderWithProviders } from '@/test/render';
import { server } from '@/test/server';

import { UserList } from './UserList';

describe('UserList', () => {
  it('shows loading status before the request resolves', () => {
    renderWithProviders(<UserList />);

    expect(screen.getByRole('status')).toHaveTextContent(/loading users/i);
  });

  it('renders one item per user after the request resolves', async () => {
    renderWithProviders(<UserList />);

    const list = await screen.findByRole('list', { name: /users/i });

    expect(within(list).getAllByRole('listitem')).toHaveLength(2);
    expect(within(list).getByText('Dash')).toBeInTheDocument();
  });

  it('shows empty state when the API returns no users', async () => {
    server.use(http.get('/api/users', () => HttpResponse.json([])));

    renderWithProviders(<UserList />);

    expect(await screen.findByText(/no users yet/i)).toBeInTheDocument();
  });

  it('shows error alert and refetches when retry is clicked', async () => {
    server.use(http.get('/api/users', () => HttpResponse.json({ message: 'boom' }, { status: 500 }), { once: true }));
    const { user } = renderWithProviders(<UserList />);

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent(/could not load users/i);

    await user.click(within(alert).getByRole('button', { name: /retry/i }));

    expect(await screen.findByRole('list', { name: /users/i })).toBeInTheDocument();
  });
});
```

`{ once: true }` makes the failing handler fire once, so the retry hits the default success handler.

## Forms

Forms use `react-hook-form` with a `zod` schema through `@hookform/resolvers/zod`. Tests fill fields the way users do and assert on validation messages exposed through `role="alert"` or `aria-describedby`.

```tsx
// src/features/profile/components/ProfileForm.tsx
import { zodResolver } from '@hookform/resolvers/zod';
import { useForm } from 'react-hook-form';
import { z } from 'zod';

export const profileSchema = z.object({
  displayName: z.string().min(2, 'Display name must be at least 2 characters'),
  role: z.enum(['admin', 'editor', 'viewer']),
  newsletter: z.boolean(),
});

export type ProfileFormValues = z.infer<typeof profileSchema>;

interface ProfileFormProps {
  defaultValues: ProfileFormValues;
  onSubmit: (values: ProfileFormValues) => Promise<void>;
}

export function ProfileForm({ defaultValues, onSubmit }: ProfileFormProps) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<ProfileFormValues>({ resolver: zodResolver(profileSchema), defaultValues });

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <label htmlFor="displayName">Display name</label>
      <input
        id="displayName"
        aria-invalid={errors.displayName ? 'true' : 'false'}
        aria-describedby={errors.displayName ? 'displayName-error' : undefined}
        {...register('displayName')}
      />
      {errors.displayName ? (
        <p id="displayName-error" role="alert">{errors.displayName.message}</p>
      ) : null}

      <label htmlFor="role">Role</label>
      <select id="role" {...register('role')}>
        <option value="admin">Admin</option>
        <option value="editor">Editor</option>
        <option value="viewer">Viewer</option>
      </select>

      <label>
        <input type="checkbox" {...register('newsletter')} />
        Subscribe to newsletter
      </label>

      <button type="submit" disabled={isSubmitting}>Save</button>
    </form>
  );
}
```

```tsx
// src/features/profile/components/ProfileForm.test.tsx
import { screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { renderWithProviders } from '@/test/render';

import { ProfileForm, type ProfileFormValues } from './ProfileForm';

const defaultValues: ProfileFormValues = { displayName: 'Dash', role: 'viewer', newsletter: false };

describe('ProfileForm', () => {
  it('calls onSubmit with updated values when form is valid', async () => {
    const onSubmit = vi.fn<(values: ProfileFormValues) => Promise<void>>().mockResolvedValue(undefined);
    const { user } = renderWithProviders(<ProfileForm defaultValues={defaultValues} onSubmit={onSubmit} />);

    await user.clear(screen.getByRole('textbox', { name: /display name/i }));
    await user.type(screen.getByRole('textbox', { name: /display name/i }), 'Sparky');
    await user.selectOptions(screen.getByRole('combobox', { name: /role/i }), 'editor');
    await user.click(screen.getByRole('checkbox', { name: /subscribe to newsletter/i }));
    await user.click(screen.getByRole('button', { name: /save/i }));

    await waitFor(() => {
      expect(onSubmit).toHaveBeenCalledWith({ displayName: 'Sparky', role: 'editor', newsletter: true });
    });
  });

  it('shows validation message and marks field invalid when display name is too short', async () => {
    const onSubmit = vi.fn<(values: ProfileFormValues) => Promise<void>>();
    const { user } = renderWithProviders(<ProfileForm defaultValues={defaultValues} onSubmit={onSubmit} />);
    const input = screen.getByRole('textbox', { name: /display name/i });

    await user.clear(input);
    await user.type(input, 'D');
    await user.click(screen.getByRole('button', { name: /save/i }));

    expect(await screen.findByRole('alert')).toHaveTextContent(/at least 2 characters/i);
    expect(input).toHaveAccessibleDescription(/at least 2 characters/i);
    expect(input).toBeInvalid();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it('disables save button while submission is pending', async () => {
    let resolveSubmit: () => void = () => undefined;
    const onSubmit = vi.fn<(values: ProfileFormValues) => Promise<void>>(
      () => new Promise<void>((resolve) => { resolveSubmit = resolve; }),
    );
    const { user } = renderWithProviders(<ProfileForm defaultValues={defaultValues} onSubmit={onSubmit} />);

    await user.click(screen.getByRole('button', { name: /save/i }));

    expect(await screen.findByRole('button', { name: /save/i })).toBeDisabled();

    resolveSubmit();
    await waitFor(() => expect(screen.getByRole('button', { name: /save/i })).toBeEnabled());
  });
});
```

## Lists and Tables

Scope queries with `within` so assertions target one row and never the whole document.

```tsx
it('marks the second order as shipped when its ship button is clicked', async () => {
  const { user } = renderWithProviders(<OrdersTable orders={orders} />);

  const row = screen.getByRole('row', { name: /order 1002/i });
  await user.click(within(row).getByRole('button', { name: /ship/i }));

  expect(within(row).getByRole('cell', { name: /shipped/i })).toBeInTheDocument();
});
```

Give rows an accessible name with `aria-label` or a header cell; a table with no names forces `getAllByRole('row')[1]` and index-based assertions.

## Portals and Dialogs

Radix and shadcn dialogs render into `document.body`. `screen` already spans the whole document, so no special container is needed.

```tsx
// src/features/orders/components/CancelOrderDialog.test.tsx
import { screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { renderWithProviders } from '@/test/render';

import { CancelOrderDialog } from './CancelOrderDialog';

describe('CancelOrderDialog', () => {
  it('opens dialog and moves focus inside when trigger is clicked', async () => {
    const { user } = renderWithProviders(<CancelOrderDialog orderId="1001" onConfirm={vi.fn()} />);

    await user.click(screen.getByRole('button', { name: /cancel order/i }));

    const dialog = await screen.findByRole('dialog', { name: /cancel order 1001/i });
    expect(dialog).toHaveFocus();
  });

  it('calls onConfirm with orderId when confirm is clicked', async () => {
    const onConfirm = vi.fn();
    const { user } = renderWithProviders(<CancelOrderDialog orderId="1001" onConfirm={onConfirm} />);

    await user.click(screen.getByRole('button', { name: /cancel order/i }));
    await user.click(await screen.findByRole('button', { name: /confirm/i }));

    expect(onConfirm).toHaveBeenCalledWith('1001');
  });

  it('closes dialog when Escape is pressed', async () => {
    const { user } = renderWithProviders(<CancelOrderDialog orderId="1001" onConfirm={vi.fn()} />);

    await user.click(screen.getByRole('button', { name: /cancel order/i }));
    await screen.findByRole('dialog');
    await user.keyboard('{Escape}');

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });
});
```

Radix components call `hasPointerCapture`, `scrollIntoView`, and `ResizeObserver`, which `jsdom` lacks. Stub them once in `src/test/setup.ts`:

```ts
// src/test/setup.ts (additions)
import { vi } from 'vitest';

class ResizeObserverStub {
  observe = vi.fn();
  unobserve = vi.fn();
  disconnect = vi.fn();
}

vi.stubGlobal('ResizeObserver', ResizeObserverStub);
Element.prototype.hasPointerCapture = () => false;
Element.prototype.scrollIntoView = () => undefined;
window.matchMedia = (query: string): MediaQueryList => ({
  matches: false,
  media: query,
  onchange: null,
  addEventListener: () => undefined,
  removeEventListener: () => undefined,
  addListener: () => undefined,
  removeListener: () => undefined,
  dispatchEvent: () => false,
});
```

## Keyboard Interaction

```tsx
it('moves focus through menu items with arrow keys', async () => {
  const { user } = renderWithProviders(<AccountMenu />);

  await user.click(screen.getByRole('button', { name: /account/i }));
  const menu = await screen.findByRole('menu');
  const items = within(menu).getAllByRole('menuitem');

  await user.keyboard('{ArrowDown}');
  expect(items[1]).toHaveFocus();

  await user.keyboard('{End}');
  expect(items.at(-1)).toHaveFocus();
});

it('submits the form when Enter is pressed in the search box', async () => {
  const onSearch = vi.fn();
  const { user } = renderWithProviders(<SearchBox onSearch={onSearch} />);

  await user.type(screen.getByRole('searchbox', { name: /search/i }), 'lamp{Enter}');

  expect(onSearch).toHaveBeenCalledWith('lamp');
});

it('reaches the primary action with Tab in order', async () => {
  const { user } = renderWithProviders(<Toolbar />);

  await user.tab();
  expect(screen.getByRole('button', { name: /new/i })).toHaveFocus();

  await user.tab();
  expect(screen.getByRole('button', { name: /import/i })).toHaveFocus();
});
```

`user.keyboard` accepts `{Key}` descriptors and `{Shift>}a{/Shift}` for held modifiers.

## Error Boundaries

Wrap the subject in `react-error-boundary` and silence the expected `console.error` for that test only.

```tsx
// src/features/reports/components/ReportPanel.test.tsx
import { screen } from '@testing-library/react';
import { ErrorBoundary } from 'react-error-boundary';
import { describe, expect, it, vi } from 'vitest';

import { renderWithProviders } from '@/test/render';

import { ReportPanel } from './ReportPanel';

function Boom(): never {
  throw new Error('render failed');
}

describe('ReportPanel', () => {
  it('renders fallback with reset button when a child throws', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const onReset = vi.fn();
    const { user } = renderWithProviders(
      <ErrorBoundary fallbackRender={({ resetErrorBoundary }) => (
        <div role="alert">
          <p>Something went wrong</p>
          <button type="button" onClick={resetErrorBoundary}>Try again</button>
        </div>
      )} onReset={onReset}>
        <ReportPanel>
          <Boom />
        </ReportPanel>
      </ErrorBoundary>,
    );

    expect(screen.getByRole('alert')).toHaveTextContent(/something went wrong/i);

    await user.click(screen.getByRole('button', { name: /try again/i }));

    expect(onReset).toHaveBeenCalledTimes(1);
    expect(consoleError).toHaveBeenCalled();
  });
});
```

`restoreMocks: true` in `vitest.config.ts` restores `console.error` after the test.

## Suspense

Components using `useSuspenseQuery` render inside a `Suspense` boundary. Assert the fallback, then the resolved content.

```tsx
// src/features/users/components/UserCard.tsx
import { useSuspenseQuery } from '@tanstack/react-query';

import { userQueries } from '../api/queries';

export function UserCard({ userId }: { userId: string }) {
  const { data: user } = useSuspenseQuery(userQueries.detail(userId));

  return (
    <article aria-labelledby={`user-${user.id}`}>
      <h2 id={`user-${user.id}`}>{user.name}</h2>
      <p>{user.email}</p>
    </article>
  );
}
```

```tsx
// src/features/users/components/UserCard.test.tsx
import { Suspense } from 'react';
import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { renderWithProviders } from '@/test/render';

import { UserCard } from './UserCard';

describe('UserCard', () => {
  it('shows fallback then user details when the query resolves', async () => {
    renderWithProviders(
      <Suspense fallback={<p role="status">Loading user</p>}>
        <UserCard userId="1" />
      </Suspense>,
    );

    expect(screen.getByRole('status')).toHaveTextContent(/loading user/i);
    expect(await screen.findByRole('heading', { name: 'Dash' })).toBeInTheDocument();
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
  });
});
```

Query errors thrown from `useSuspenseQuery` propagate to the nearest error boundary; combine the Suspense and error boundary patterns to test the failure path.

## Data Routes

Components that call `useLoaderData`, `useParams`, or `useNavigate` need a route context. Use `createRoutesStub` from `react-router` instead of `MemoryRouter` when a loader or action is involved.

```tsx
// src/features/orders/routes/OrderDetailRoute.test.tsx
import { screen } from '@testing-library/react';
import { createRoutesStub } from 'react-router';
import { describe, expect, it } from 'vitest';

import { renderWithProviders } from '@/test/render';

import { OrderDetailRoute } from './OrderDetailRoute';

describe('OrderDetailRoute', () => {
  it('renders order number from loader data', async () => {
    const Stub = createRoutesStub([
      {
        path: '/orders/:orderId',
        Component: OrderDetailRoute,
        loader: () => ({ order: { id: '1001', status: 'shipped' } }),
      },
    ]);

    renderWithProviders(<Stub initialEntries={['/orders/1001']} />);

    expect(await screen.findByRole('heading', { name: /order 1001/i })).toBeInTheDocument();
  });

  it('navigates back to orders list when back is clicked', async () => {
    const Stub = createRoutesStub([
      { path: '/orders', Component: () => <h1>Orders</h1> },
      {
        path: '/orders/:orderId',
        Component: OrderDetailRoute,
        loader: () => ({ order: { id: '1001', status: 'shipped' } }),
      },
    ]);
    const { user } = renderWithProviders(<Stub initialEntries={['/orders/1001']} />);

    await user.click(await screen.findByRole('link', { name: /back to orders/i }));

    expect(await screen.findByRole('heading', { name: 'Orders' })).toBeInTheDocument();
  });
});
```

## Accessibility Assertions

Run `axe` on every page-level component once, in addition to role-based queries.

```tsx
import { axe } from 'vitest-axe';

it('has no accessibility violations', async () => {
  const { container } = renderWithProviders(<LoginForm onSubmit={vi.fn()} />);

  expect(await axe(container)).toHaveNoViolations();
});
```

Register the matcher in `src/test/setup.ts` with `import 'vitest-axe/extend-expect';`.

## Module-Boundary Mocks

Mock only what crosses a process or package boundary: analytics SDKs, storage adapters, third-party clients. Never `vi.mock` a sibling component, a hook inside the feature, or `@tanstack/react-query`.

```tsx
import { screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { track } from '@acme/analytics';
import { renderWithProviders } from '@/test/render';

import { LoginForm } from './LoginForm';

vi.mock('@acme/analytics', () => ({ track: vi.fn() }));

describe('LoginForm analytics', () => {
  it('tracks sign_in when submit succeeds', async () => {
    const { user } = renderWithProviders(<LoginForm onSubmit={vi.fn().mockResolvedValue(undefined)} />);

    await user.type(screen.getByRole('textbox', { name: /email/i }), 'dash@example.com');
    await user.type(screen.getByLabelText(/password/i), 'hunter22');
    await user.click(screen.getByRole('button', { name: /sign in/i }));

    expect(vi.mocked(track)).toHaveBeenCalledWith('sign_in', { method: 'password' });
  });
});
```

`clearMocks: true` in `vitest.config.ts` resets call history between tests.

## Fake Timers

Use fake timers only for code that depends on time: debounce, polling, toasts that auto-dismiss. Restore real timers in `afterEach`.

```ts
// src/features/search/hooks/useDebouncedValue.test.ts
import { act, renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { useDebouncedValue } from './useDebouncedValue';

describe('useDebouncedValue', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('returns debounced value after delay elapses', () => {
    const { result, rerender } = renderHook(({ value }) => useDebouncedValue(value, 300), {
      initialProps: { value: 'a' },
    });

    rerender({ value: 'ab' });
    expect(result.current).toBe('a');

    act(() => vi.advanceTimersByTime(300));
    expect(result.current).toBe('ab');
  });
});
```

When a component test needs both `user-event` and fake timers, create the user with `advanceTimers` so typing does not hang:

```tsx
import userEvent from '@testing-library/user-event';

vi.useFakeTimers();
const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
render(<SearchBox onSearch={onSearch} />);

await user.type(screen.getByRole('searchbox', { name: /search/i }), 'lamp');
act(() => vi.advanceTimersByTime(300));

expect(onSearch).toHaveBeenCalledWith('lamp');
```

Wrap timer advances in `act` whenever they trigger a state update.
