# Network Mocking with `msw`

`msw` intercepts requests at the network layer, so tests exercise the real API client, `zod` parsing, and `@tanstack/react-query` hooks. Nothing in application code changes for tests.

## Handler Organization

One handler file per API resource, aggregated in `src/test/handlers.ts`.

```text
src/test/
  handlers/
    users.ts
    orders.ts
  handlers.ts        # export const handlers = [...usersHandlers, ...ordersHandlers]
  server.ts          # setupServer(...handlers)
  browser.ts         # setupWorker(...handlers) for dev and Storybook
  factories.ts       # buildUser(), buildOrder()
  setup.ts           # listen / resetHandlers / close
```

```ts
// src/test/factories.ts
import type { OrderDto, UserDto } from '@acme/api-client';

let sequence = 0;

export function buildUser(overrides: Partial<UserDto> = {}): UserDto {
  sequence += 1;
  return {
    id: String(sequence),
    name: `User ${sequence}`,
    email: `user${sequence}@example.com`,
    ...overrides,
  };
}

export function buildOrder(overrides: Partial<OrderDto> = {}): OrderDto {
  sequence += 1;
  return {
    id: String(1000 + sequence),
    status: 'open',
    total: 100,
    ...overrides,
  };
}
```

```ts
// src/test/handlers/users.ts
import { http, HttpResponse } from 'msw';

import { buildUser } from '../factories';

export const defaultUsers = [
  buildUser({ id: '1', name: 'Dash', email: 'dash@example.com' }),
  buildUser({ id: '2', name: 'Sparky', email: 'sparky@example.com' }),
];

export const usersHandlers = [
  http.get('/api/users', () => HttpResponse.json(defaultUsers)),
  http.get('/api/users/:id', ({ params }) => {
    const user = defaultUsers.find((candidate) => candidate.id === params['id']);
    return user
      ? HttpResponse.json(user)
      : HttpResponse.json({ message: 'Not found' }, { status: 404 });
  }),
];
```

```ts
// src/test/handlers.ts
import { ordersHandlers } from './handlers/orders';
import { usersHandlers } from './handlers/users';

export const handlers = [...usersHandlers, ...ordersHandlers];
```

Match the base URL the client uses. When the client reads `import.meta.env['VITE_API_URL']`, set it in `.env.test` and use the same value in handlers, or use relative paths everywhere.

## Server Setup

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

| Option                         | Effect                                                           |
| ------------------------------ | ---------------------------------------------------------------- |
| `onUnhandledRequest: 'error'`  | Unmocked requests fail the test; use this in test setup          |
| `onUnhandledRequest: 'bypass'` | Unmocked requests hit the network; use only in Storybook and dev |
| `server.resetHandlers()`       | Removes `server.use` overrides; call in `afterEach`              |
| `server.restoreHandlers()`     | Re-enables handlers marked `{ once: true }` that already fired   |

## Per-Test Overrides

`server.use` prepends handlers, so the override wins for the rest of the test.

```ts
import { http, HttpResponse } from 'msw';

import { server } from '@/test/server';

it('shows empty state when there are no users', async () => {
  server.use(http.get('/api/users', () => HttpResponse.json([])));

  renderWithProviders(<UserList />);

  expect(await screen.findByText(/no users yet/i)).toBeInTheDocument();
});
```

## Error Cases

| Scenario           | Handler                                                                                   |
| ------------------ | ----------------------------------------------------------------------------------------- |
| HTTP error status  | `() => HttpResponse.json({ message: 'Forbidden' }, { status: 403 })`                      |
| Network failure    | `() => HttpResponse.error()`                                                              |
| Malformed body     | `() => HttpResponse.text('<html>', { status: 200 })`                                      |
| Schema violation   | `() => HttpResponse.json({ id: 1 })` where the `zod` schema expects `id: string`          |
| Fail once, then OK | `http.get(url, () => HttpResponse.error(), { once: true })` on top of the default handler |

```ts
it('shows offline message when the network fails', async () => {
  server.use(http.get('/api/users', () => HttpResponse.error()));

  renderWithProviders(<UserList />);

  expect(await screen.findByRole('alert')).toHaveTextContent(/could not load users/i);
});

it('throws ApiError when response fails schema validation', async () => {
  server.use(http.get('/api/users/:id', () => HttpResponse.json({ id: 1, name: 42 })));

  await expect(usersClient.getUser('1')).rejects.toBeInstanceOf(ApiError);
});
```

## Latency

Use `delay` to test loading states that depend on timing, such as skeletons that appear only after 200 ms.

```ts
import { delay, http, HttpResponse } from 'msw';

server.use(
  http.get('/api/users', async () => {
    await delay(500);
    return HttpResponse.json(defaultUsers);
  }),
);
```

`delay('infinite')` keeps a request pending forever, which is the correct way to assert on a loading state without racing the response.

```ts
it('shows skeleton while the request is pending', () => {
  server.use(http.get('/api/users', () => delay('infinite')));

  renderWithProviders(<UserList />);

  expect(screen.getByRole('status')).toHaveTextContent(/loading users/i);
});
```

Combine `delay` with `vi.useFakeTimers()` only when the component also uses timers; `msw` delays run on real timers by default.

## Typed Handlers with `zod`

Type the path params, request body, and response body so a handler that drifts from the API contract fails to compile. Parse the request body with the same `zod` schema the client uses.

```ts
// src/test/handlers/orders.ts
import { http, HttpResponse, type PathParams } from 'msw';

import { createOrderSchema, type CreateOrderInput, type OrderDto } from '@acme/api-client';

import { buildOrder } from '../factories';

type OrderParams = PathParams<'orderId'>;
type ErrorBody = { message: string; issues?: unknown };

export const ordersHandlers = [
  http.post<never, CreateOrderInput, OrderDto | ErrorBody>('/api/orders', async ({ request }) => {
    const parsed = createOrderSchema.safeParse(await request.json());
    if (!parsed.success) {
      return HttpResponse.json({ message: 'Invalid order', issues: parsed.error.issues }, { status: 422 });
    }
    return HttpResponse.json(buildOrder({ ...parsed.data, status: 'open' }), { status: 201 });
  }),

  http.patch<OrderParams, Partial<OrderDto>, OrderDto | ErrorBody>('/api/orders/:orderId', async ({ params, request }) => {
    const patch = await request.json();
    return HttpResponse.json(buildOrder({ id: params.orderId, ...patch }));
  }),
];
```

Asserting on the request payload belongs in the handler, not in a spy on `fetch`:

```ts
it('sends the selected items when the order is placed', async () => {
  const received: CreateOrderInput[] = [];
  server.use(
    http.post<never, CreateOrderInput>('/api/orders', async ({ request }) => {
      received.push(createOrderSchema.parse(await request.json()));
      return HttpResponse.json(buildOrder(), { status: 201 });
    }),
  );
  const { user } = renderWithProviders(<Checkout items={items} />);

  await user.click(screen.getByRole('button', { name: /place order/i }));

  await waitFor(() => expect(received).toHaveLength(1));
  expect(received[0]).toEqual({ items: [{ sku: 'LAMP-1', quantity: 2 }] });
});
```

## Browser Worker for Dev and Storybook

The same handlers power local development without a backend and Storybook stories.

```ts
// src/test/browser.ts
import { setupWorker } from 'msw/browser';

import { handlers } from './handlers';

export const worker = setupWorker(...handlers);
```

```ts
// src/main.tsx (before rendering)
if (import.meta.env.DEV && import.meta.env['VITE_MOCK_API'] === 'true') {
  const { worker } = await import('./test/browser');
  await worker.start({ onUnhandledRequest: 'bypass' });
}
```

Generate the service worker once with `pnpm exec msw init public/ --save`.

## Anti-Patterns

| Anti-Pattern                                        | Problem                                              | Correct Approach                                  |
| --------------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------- |
| `vi.spyOn(globalThis, 'fetch')`                     | Skips the client and parser; response shape drifts   | `msw` handler returning the real DTO shape        |
| `vi.mock('@acme/api-client')`                       | Tests never see a real response or parse failure     | `msw` at the network boundary                     |
| Handlers defined inside components' test files only | Duplicated fixtures; no shared happy path            | Default handlers in `src/test/handlers/`          |
| `onUnhandledRequest: 'warn'` in tests               | Missing handlers pass silently with `undefined` data | `'error'`                                         |
| Forgetting `server.resetHandlers()`                 | Overrides leak into the next test                    | `afterEach(() => server.resetHandlers())`         |
| Asserting the request through `fetch` call args     | Couples tests to transport details                   | Capture the body inside the handler               |
| Hand-written response literals with wrong types     | Handlers drift from the API contract                 | `http.get<Params, Body, Response>` with DTO types |
