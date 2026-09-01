# Worked Example: Adding an `orders` Feature

End-to-end steps for a new domain, from data package to route. Every file is complete; tests follow [testing.md](testing.md).

---

## Step 1: Data package `packages/orders-api-client`

```bash
mkdir -p packages/orders-api-client/src/dto
cd packages/orders-api-client && pnpm init
pnpm add zod
pnpm add -D tsup typescript vitest @vitest/coverage-v8 msw
```

Set `package.json` fields as in [package-manifests.md](package-manifests.md) (name `@acme/orders-api-client`, `exports`, `sideEffects: false`, scripts).

### `src/dto/order-dto.ts`

```ts
import { z } from 'zod';

export const orderItemDtoSchema = z.object({
  sku: z.string(),
  quantity: z.number().int().positive(),
  unit_price_cents: z.number().int().nonnegative(),
});

export const orderDtoSchema = z.object({
  id: z.string(),
  status: z.enum(['pending', 'paid', 'shipped', 'cancelled']),
  currency: z.string().length(3),
  placed_at: z.iso.datetime(),
  items: orderItemDtoSchema.array(),
});

export type OrderDto = z.infer<typeof orderDtoSchema>;
export type OrderItemDto = z.infer<typeof orderItemDtoSchema>;
```

### `src/errors.ts`

```ts
export class OrdersApiError extends Error {
  readonly status: number;

  constructor(status: number, message = `Orders API request failed with status ${status}`) {
    super(message);
    this.name = 'OrdersApiError';
    this.status = status;
  }
}
```

### `src/orders-api-client.ts`

```ts
import type { ZodType } from 'zod';

import { orderDtoSchema, type OrderDto } from './dto/order-dto';
import { OrdersApiError } from './errors';

export type OrdersApiClientOptions = { baseUrl: string; fetch?: typeof fetch };

export type OrdersApiClient = {
  getOrders(): Promise<OrderDto[]>;
  getOrder(id: string): Promise<OrderDto>;
  cancelOrder(id: string): Promise<OrderDto>;
};

export function createOrdersApiClient({ baseUrl, fetch: fetchFn = fetch }: OrdersApiClientOptions): OrdersApiClient {
  async function request<T>(path: string, init: RequestInit, schema: ZodType<T>): Promise<T> {
    const response = await fetchFn(`${baseUrl}${path}`, {
      ...init,
      headers: { accept: 'application/json', ...init.headers },
    });
    if (!response.ok) {
      throw new OrdersApiError(response.status);
    }
    return schema.parse(await response.json());
  }

  return {
    getOrders: () => request('/orders', { method: 'GET' }, orderDtoSchema.array()),
    getOrder: (id) => request(`/orders/${encodeURIComponent(id)}`, { method: 'GET' }, orderDtoSchema),
    cancelOrder: (id) => request(`/orders/${encodeURIComponent(id)}/cancel`, { method: 'POST' }, orderDtoSchema),
  };
}
```

### `src/index.ts`

```ts
export { orderDtoSchema, orderItemDtoSchema, type OrderDto, type OrderItemDto } from './dto/order-dto';
export { OrdersApiError } from './errors';
export { createOrdersApiClient, type OrdersApiClient, type OrdersApiClientOptions } from './orders-api-client';
```

### `src/orders-api-client.test.ts`

```ts
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import { OrdersApiError } from './errors';
import { createOrdersApiClient } from './orders-api-client';

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

const orderJson = {
  id: 'ord_1',
  status: 'paid',
  currency: 'USD',
  placed_at: '2025-03-01T10:00:00Z',
  items: [{ sku: 'SKU-1', quantity: 2, unit_price_cents: 1250 }],
};

describe('createOrdersApiClient', () => {
  const client = createOrdersApiClient({ baseUrl });

  it('getOrders returns parsed DTOs', async () => {
    server.use(http.get(`${baseUrl}/orders`, () => HttpResponse.json([orderJson])));

    await expect(client.getOrders()).resolves.toEqual([orderJson]);
  });

  it('getOrder encodes the id', async () => {
    server.use(http.get(`${baseUrl}/orders/ord%2F1`, () => HttpResponse.json({ ...orderJson, id: 'ord/1' })));

    await expect(client.getOrder('ord/1')).resolves.toMatchObject({ id: 'ord/1' });
  });

  it('cancelOrder posts and returns the DTO', async () => {
    server.use(http.post(`${baseUrl}/orders/ord_1/cancel`, () => HttpResponse.json({ ...orderJson, status: 'cancelled' })));

    await expect(client.cancelOrder('ord_1')).resolves.toMatchObject({ status: 'cancelled' });
  });

  it('throws OrdersApiError on non-2xx', async () => {
    server.use(http.get(`${baseUrl}/orders`, () => HttpResponse.text('', { status: 503 })));

    await expect(client.getOrders()).rejects.toBeInstanceOf(OrdersApiError);
  });

  it('throws on an invalid status value', async () => {
    server.use(http.get(`${baseUrl}/orders`, () => HttpResponse.json([{ ...orderJson, status: 'lost' }])));

    await expect(client.getOrders()).rejects.toThrow();
  });
});
```

---

## Step 2: Repository package `packages/orders-repository`

```bash
mkdir -p packages/orders-repository/src/models
cd packages/orders-repository && pnpm init
pnpm add @acme/orders-api-client@workspace:*
pnpm add -D tsup typescript vitest @vitest/coverage-v8
```

### `src/models/order.ts`

```ts
import type { OrderDto } from '@acme/orders-api-client';

export type OrderId = string & { readonly __brand: 'OrderId' };

export function toOrderId(value: string): OrderId {
  return value as OrderId;
}

export type OrderStatus = 'pending' | 'paid' | 'shipped' | 'cancelled';

export type Money = { amount: number; currency: string };

export type Order = {
  id: OrderId;
  status: OrderStatus;
  total: Money;
  itemCount: number;
  placedAt: Date;
  canCancel: boolean;
};

const cancellableStatuses: ReadonlySet<OrderStatus> = new Set(['pending', 'paid']);

export function orderFromDto(dto: OrderDto): Order {
  const totalCents = dto.items.reduce((sum, item) => sum + item.quantity * item.unit_price_cents, 0);

  return {
    id: toOrderId(dto.id),
    status: dto.status,
    total: { amount: totalCents / 100, currency: dto.currency },
    itemCount: dto.items.reduce((sum, item) => sum + item.quantity, 0),
    placedAt: new Date(dto.placed_at),
    canCancel: cancellableStatuses.has(dto.status),
  };
}
```

### `src/errors.ts`

```ts
import type { OrderId } from './models/order';

export class OrderNotFoundError extends Error {
  constructor(readonly id: OrderId) {
    super(`Order ${id} was not found`);
    this.name = 'OrderNotFoundError';
  }
}

export class OrderNotCancellableError extends Error {
  constructor(readonly id: OrderId) {
    super(`Order ${id} can no longer be cancelled`);
    this.name = 'OrderNotCancellableError';
  }
}
```

### `src/orders-repository.ts`

```ts
import { OrdersApiError, type OrdersApiClient } from '@acme/orders-api-client';

import { OrderNotCancellableError, OrderNotFoundError } from './errors';
import { orderFromDto, type Order, type OrderId } from './models/order';

export type OrdersRepository = {
  getOrders(): Promise<Order[]>;
  getOrder(id: OrderId): Promise<Order>;
  cancelOrder(id: OrderId): Promise<Order>;
};

export function createOrdersRepository({ apiClient }: { apiClient: OrdersApiClient }): OrdersRepository {
  function translate(error: unknown, id: OrderId): never {
    if (error instanceof OrdersApiError && error.status === 404) throw new OrderNotFoundError(id);
    if (error instanceof OrdersApiError && error.status === 409) throw new OrderNotCancellableError(id);
    throw error;
  }

  return {
    async getOrders() {
      const dtos = await apiClient.getOrders();
      return dtos.map(orderFromDto).sort((a, b) => b.placedAt.getTime() - a.placedAt.getTime());
    },
    async getOrder(id) {
      try {
        return orderFromDto(await apiClient.getOrder(id));
      } catch (error) {
        return translate(error, id);
      }
    },
    async cancelOrder(id) {
      try {
        return orderFromDto(await apiClient.cancelOrder(id));
      } catch (error) {
        return translate(error, id);
      }
    },
  };
}
```

### `src/index.ts`

```ts
export { OrderNotCancellableError, OrderNotFoundError } from './errors';
export { orderFromDto, toOrderId, type Money, type Order, type OrderId, type OrderStatus } from './models/order';
export { createOrdersRepository, type OrdersRepository } from './orders-repository';
```

### `src/orders-repository.test.ts`

```ts
import { OrdersApiError, type OrderDto, type OrdersApiClient } from '@acme/orders-api-client';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { OrderNotCancellableError, OrderNotFoundError } from './errors';
import { toOrderId } from './models/order';
import { createOrdersRepository, type OrdersRepository } from './orders-repository';

type FakeClient = { [K in keyof OrdersApiClient]: ReturnType<typeof vi.fn<OrdersApiClient[K]>> };

const dto: OrderDto = {
  id: 'ord_1',
  status: 'paid',
  currency: 'USD',
  placed_at: '2025-03-01T10:00:00Z',
  items: [
    { sku: 'A', quantity: 2, unit_price_cents: 1250 },
    { sku: 'B', quantity: 1, unit_price_cents: 500 },
  ],
};

describe('createOrdersRepository', () => {
  let apiClient: FakeClient;
  let subject: OrdersRepository;

  beforeEach(() => {
    apiClient = {
      getOrders: vi.fn<OrdersApiClient['getOrders']>(),
      getOrder: vi.fn<OrdersApiClient['getOrder']>(),
      cancelOrder: vi.fn<OrdersApiClient['cancelOrder']>(),
    };
    subject = createOrdersRepository({ apiClient });
  });

  it('maps totals, item counts, dates, and cancellability', async () => {
    apiClient.getOrder.mockResolvedValue(dto);

    await expect(subject.getOrder(toOrderId('ord_1'))).resolves.toEqual({
      id: 'ord_1',
      status: 'paid',
      total: { amount: 30, currency: 'USD' },
      itemCount: 3,
      placedAt: new Date('2025-03-01T10:00:00Z'),
      canCancel: true,
    });
  });

  it('marks shipped orders as not cancellable', async () => {
    apiClient.getOrder.mockResolvedValue({ ...dto, status: 'shipped' });

    await expect(subject.getOrder(toOrderId('ord_1'))).resolves.toMatchObject({ canCancel: false });
  });

  it('sorts orders newest first', async () => {
    apiClient.getOrders.mockResolvedValue([
      { ...dto, id: 'old', placed_at: '2024-01-01T00:00:00Z' },
      { ...dto, id: 'new', placed_at: '2025-01-01T00:00:00Z' },
    ]);

    const result = await subject.getOrders();

    expect(result.map((order) => order.id)).toEqual(['new', 'old']);
  });

  it('translates 404 to OrderNotFoundError', async () => {
    apiClient.getOrder.mockRejectedValue(new OrdersApiError(404));

    await expect(subject.getOrder(toOrderId('x'))).rejects.toBeInstanceOf(OrderNotFoundError);
  });

  it('translates 409 on cancel to OrderNotCancellableError', async () => {
    apiClient.cancelOrder.mockRejectedValue(new OrdersApiError(409));

    await expect(subject.cancelOrder(toOrderId('ord_1'))).rejects.toBeInstanceOf(OrderNotCancellableError);
  });

  it('rethrows other errors', async () => {
    apiClient.getOrders.mockRejectedValue(new OrdersApiError(500));

    await expect(subject.getOrders()).rejects.toMatchObject({ status: 500 });
  });
});
```

---

## Step 3: Wire the app

```bash
pnpm --filter @acme/web add @acme/orders-repository@workspace:* @acme/orders-api-client@workspace:*
```

### `src/app/repositories.tsx` (change)

```ts
import type { OrdersRepository } from '@acme/orders-repository';
import type { TodosRepository } from '@acme/todos-repository';

export type Repositories = { todos: TodosRepository; orders: OrdersRepository };
```

### `src/app/bootstrap.ts` (change)

```ts
import { createOrdersApiClient } from '@acme/orders-api-client';
import { createOrdersRepository } from '@acme/orders-repository';

export function createRepositories(config: AppConfig): Repositories {
  const todosApiClient = createTodosApiClient({ baseUrl: config.apiBaseUrl });
  const ordersApiClient = createOrdersApiClient({ baseUrl: config.apiBaseUrl });

  return {
    todos: createTodosRepository({ apiClient: todosApiClient }),
    orders: createOrdersRepository({ apiClient: ordersApiClient }),
  };
}
```

### `src/test/fakes.ts` (change)

```ts
export type FakeOrdersRepository = { [K in keyof OrdersRepository]: ReturnType<typeof vi.fn<OrdersRepository[K]>> };

export function createFakeOrdersRepository(): FakeOrdersRepository {
  return {
    getOrders: vi.fn<OrdersRepository['getOrders']>().mockResolvedValue([]),
    getOrder: vi.fn<OrdersRepository['getOrder']>(),
    cancelOrder: vi.fn<OrdersRepository['cancelOrder']>(),
  };
}

export function createFakeRepositories(overrides: Partial<Repositories> = {}): Repositories {
  return { todos: createFakeTodosRepository(), orders: createFakeOrdersRepository(), ...overrides };
}
```

---

## Step 4: Feature folder `src/features/orders`

### `api/ordersQueries.ts`

```ts
import { queryOptions } from '@tanstack/react-query';
import type { OrderId, OrdersRepository } from '@acme/orders-repository';

export const ordersKeys = {
  all: ['orders'] as const,
  lists: () => [...ordersKeys.all, 'list'] as const,
  list: () => [...ordersKeys.lists()] as const,
  details: () => [...ordersKeys.all, 'detail'] as const,
  detail: (id: OrderId) => [...ordersKeys.details(), id] as const,
};

export function ordersListOptions(repository: OrdersRepository) {
  return queryOptions({ queryKey: ordersKeys.list(), queryFn: () => repository.getOrders() });
}

export function orderDetailOptions(repository: OrdersRepository, id: OrderId) {
  return queryOptions({ queryKey: ordersKeys.detail(id), queryFn: () => repository.getOrder(id) });
}
```

### `api/useOrdersQuery.ts`

```ts
import { useSuspenseQuery } from '@tanstack/react-query';

import { useRepositories } from '@/app/repositories';

import { ordersListOptions } from './ordersQueries';

export function useOrdersQuery() {
  const { orders } = useRepositories();
  return useSuspenseQuery(ordersListOptions(orders));
}
```

### `api/useCancelOrderMutation.ts`

```ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import type { OrderId } from '@acme/orders-repository';

import { useRepositories } from '@/app/repositories';

import { ordersKeys } from './ordersQueries';

export function useCancelOrderMutation() {
  const { orders } = useRepositories();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: OrderId) => orders.cancelOrder(id),
    onSuccess: async (order) => {
      queryClient.setQueryData(ordersKeys.detail(order.id), order);
      await queryClient.invalidateQueries({ queryKey: ordersKeys.lists() });
    },
  });
}
```

### `components/OrdersView.tsx`

```tsx
import type { Order, OrderId } from '@acme/orders-repository';
import { Button } from '@acme/ui';

import { formatMoney } from '@/lib/formatMoney';

export type OrdersViewProps = {
  orders: readonly Order[];
  cancellingId: OrderId | null;
  onCancel: (id: OrderId) => void;
};

export function OrdersView({ orders, cancellingId, onCancel }: OrdersViewProps) {
  if (orders.length === 0) {
    return <p>You have no orders.</p>;
  }

  return (
    <table>
      <caption>Orders</caption>
      <thead>
        <tr>
          <th scope="col">Order</th>
          <th scope="col">Status</th>
          <th scope="col">Total</th>
          <th scope="col">Actions</th>
        </tr>
      </thead>
      <tbody>
        {orders.map((order) => (
          <tr key={order.id}>
            <th scope="row">{order.id}</th>
            <td>{order.status}</td>
            <td>{formatMoney(order.total)}</td>
            <td>
              {order.canCancel && (
                <Button
                  variant="outline"
                  size="sm"
                  isLoading={cancellingId === order.id}
                  onClick={() => {
                    onCancel(order.id);
                  }}
                >
                  Cancel order {order.id}
                </Button>
              )}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
```

### `components/OrdersView.test.tsx`

```tsx
import { toOrderId, type Order } from '@acme/orders-repository';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';

import { OrdersView } from './OrdersView';

const paid: Order = {
  id: toOrderId('ord_1'),
  status: 'paid',
  total: { amount: 30, currency: 'USD' },
  itemCount: 3,
  placedAt: new Date(0),
  canCancel: true,
};
const shipped: Order = { ...paid, id: toOrderId('ord_2'), status: 'shipped', canCancel: false };

describe('OrdersView', () => {
  it('renders a row per order', () => {
    render(<OrdersView orders={[paid, shipped]} cancellingId={null} onCancel={vi.fn()} />);

    expect(screen.getAllByRole('row')).toHaveLength(3);
    expect(screen.getByRole('rowheader', { name: 'ord_1' })).toBeInTheDocument();
  });

  it('offers cancel only for cancellable orders', () => {
    render(<OrdersView orders={[paid, shipped]} cancellingId={null} onCancel={vi.fn()} />);

    expect(screen.getByRole('button', { name: 'Cancel order ord_1' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Cancel order ord_2' })).not.toBeInTheDocument();
  });

  it('calls onCancel with the order id', async () => {
    const user = userEvent.setup();
    const onCancel = vi.fn();
    render(<OrdersView orders={[paid]} cancellingId={null} onCancel={onCancel} />);

    await user.click(screen.getByRole('button', { name: 'Cancel order ord_1' }));

    expect(onCancel).toHaveBeenCalledWith(toOrderId('ord_1'));
  });

  it('shows the cancelling order as busy', () => {
    render(<OrdersView orders={[paid]} cancellingId={paid.id} onCancel={vi.fn()} />);

    expect(screen.getByRole('button', { name: 'Cancel order ord_1' })).toHaveAttribute('aria-busy', 'true');
  });

  it('renders an empty state', () => {
    render(<OrdersView orders={[]} cancellingId={null} onCancel={vi.fn()} />);

    expect(screen.getByText('You have no orders.')).toBeInTheDocument();
  });
});
```

### `routes/OrdersPage.tsx`

```tsx
import { useCancelOrderMutation } from '../api/useCancelOrderMutation';
import { useOrdersQuery } from '../api/useOrdersQuery';
import { OrdersView } from '../components/OrdersView';

export function OrdersPage() {
  const { data: orders } = useOrdersQuery();
  const cancel = useCancelOrderMutation();

  return (
    <OrdersView
      orders={orders}
      cancellingId={cancel.isPending ? cancel.variables : null}
      onCancel={(id) => cancel.mutate(id)}
    />
  );
}
```

### `routes/OrdersPage.test.tsx`

```tsx
import { toOrderId, type Order } from '@acme/orders-repository';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { createFakeOrdersRepository, createFakeRepositories } from '@/test/fakes';
import { renderWithProviders } from '@/test/render';

import { OrdersPage } from './OrdersPage';

const order: Order = {
  id: toOrderId('ord_1'),
  status: 'paid',
  total: { amount: 30, currency: 'USD' },
  itemCount: 3,
  placedAt: new Date(0),
  canCancel: true,
};

describe('OrdersPage', () => {
  it('loads orders and cancels one', async () => {
    const user = userEvent.setup();
    const orders = createFakeOrdersRepository();
    orders.getOrders.mockResolvedValue([order]);
    orders.cancelOrder.mockResolvedValue({ ...order, status: 'cancelled', canCancel: false });

    renderWithProviders(<OrdersPage />, { repositories: createFakeRepositories({ orders }) });

    await user.click(await screen.findByRole('button', { name: 'Cancel order ord_1' }));

    expect(orders.cancelOrder).toHaveBeenCalledWith(order.id);
  });
});
```

### `index.ts`

```ts
export { ordersKeys } from './api/ordersQueries';
export { OrdersPage } from './routes/OrdersPage';
```

---

## Step 5: Register the route

```tsx
// src/app/router.tsx (addition inside children)
{
  path: 'orders',
  lazy: async () => {
    const { OrdersPage } = await import('@/features/orders');
    return { Component: OrdersPage };
  },
},
```

---

## Step 6: Verify

```bash
pnpm install
pnpm turbo run build --filter=@acme/orders-repository...
pnpm lint && pnpm typecheck && pnpm test:coverage
```

Checklist:

- `pnpm lint` passes with no `boundaries/*` errors; `@acme/orders-api-client` is imported only in `src/app/bootstrap.ts`
- Both packages report 100% coverage
- `OrdersView` renders from props alone; `OrdersPage` is the only file in the feature that calls hooks
- `features/orders/index.ts` exports `OrdersPage` and `ordersKeys` only
