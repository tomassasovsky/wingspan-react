# Loading

## Diagnosing Waterfalls

A waterfall is any request that starts only after another finishes when the two are independent. Find them in the Network panel: staggered start times with idle gaps between them.

| Waterfall                                   | Cause                                                | Fix                                                                                                       |
| ------------------------------------------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Route chunk, then data                      | Data fetch starts inside the lazily loaded component | Fetch in the route `loader`; the loader lives in the same lazy module and runs in parallel with rendering |
| Parent query, then child query              | Child mounts after parent data arrives               | Hoist both queries to the parent with `useSuspenseQueries`, or prefetch the child in the loader           |
| Query A, then query B in the same component | Two sequential `await` calls                         | `Promise.all` or `useSuspenseQueries`                                                                     |
| Auth check, then everything                 | App renders nothing until the session resolves       | Prefetch the session in the root loader; stream the shell                                                 |
| Font, then text                             | Font declared in CSS, discovered late                | `<link rel="preload" as="font">` or `next/font`                                                           |

## Prefetching in Route Loaders

Loaders start data fetching when navigation begins, before the route component renders. `ensureQueryData` returns cached data when fresh and fetches otherwise.

```ts
// src/features/orders/api/queries.ts
import { queryOptions } from '@tanstack/react-query';

import { ordersRepository } from '@/app/repositories';

export const orderQueries = {
  all: () => ['orders'] as const,
  list: (filters: { status: string }) =>
    queryOptions({
      queryKey: [...orderQueries.all(), 'list', filters] as const,
      queryFn: () => ordersRepository.list(filters),
      staleTime: 30_000,
    }),
  detail: (orderId: string) =>
    queryOptions({
      queryKey: [...orderQueries.all(), 'detail', orderId] as const,
      queryFn: () => ordersRepository.get(orderId),
      staleTime: 30_000,
    }),
};
```

```tsx
// src/features/orders/routes/OrderDetailRoute.tsx
import { useSuspenseQueries } from '@tanstack/react-query';
import { useParams, type LoaderFunctionArgs } from 'react-router';

import { queryClient } from '@/app/queryClient';
import { customerQueries } from '@/features/customers/api/queries';

import { orderQueries } from '../api/queries';
import { OrderDetailView } from '../components/OrderDetailView';

export async function loader({ params }: LoaderFunctionArgs) {
  const orderId = params['orderId'];
  if (!orderId) throw new Response('Not found', { status: 404 });

  // Kick off both requests; do not await sequentially.
  const order = await queryClient.ensureQueryData(orderQueries.detail(orderId));
  void queryClient.prefetchQuery(customerQueries.detail(order.customerId));
  return null;
}

export function Component() {
  const { orderId = '' } = useParams();
  const [{ data: order }] = useSuspenseQueries({ queries: [orderQueries.detail(orderId)] });
  const [{ data: customer }] = useSuspenseQueries({ queries: [customerQueries.detail(order.customerId)] });

  return <OrderDetailView order={order} customer={customer} />;
}
```

The customer request depends on the order, so it cannot start in parallel; prefetching it in the loader still starts it before the component renders.

## Prefetch on Intent

```tsx
import { Link } from 'react-router';

<Link to={`/orders/${order.id}`} prefetch="intent">
  {order.id}
</Link>
```

`prefetch="intent"` loads the route module and runs its loader on hover or focus. Next `<Link>` prefetches routes in the viewport by default; set `prefetch={false}` on lists with hundreds of links.

Prefetch a query on hover for components outside the router:

```tsx
import { useQueryClient } from '@tanstack/react-query';

export function OrderRow({ order }: { order: Order }) {
  const queryClient = useQueryClient();
  const prefetch = () => void queryClient.prefetchQuery(orderQueries.detail(order.id));

  return (
    <tr onPointerEnter={prefetch} onFocus={prefetch}>
      {/* ... */}
    </tr>
  );
}
```

## Parallel Queries

```tsx
import { useSuspenseQueries } from '@tanstack/react-query';

export function DashboardPage() {
  const [{ data: orders }, { data: customers }, { data: metrics }] = useSuspenseQueries({
    queries: [
      orderQueries.list({ status: 'open' }),
      customerQueries.list(),
      metricsQueries.summary(),
    ],
  });

  return <DashboardView orders={orders} customers={customers} metrics={metrics} />;
}
```

Three `useSuspenseQuery` calls in a row suspend one at a time; `useSuspenseQueries` starts all three together.

## Streaming and Suspense Boundaries

Place `Suspense` boundaries around the slow parts, not the whole page. The shell and fast sections paint first; each slow section streams in when ready.

```tsx
// app/dashboard/page.tsx (Next server component)
import { Suspense } from 'react';

import { MetricsCards, MetricsSkeleton } from './MetricsCards';
import { RecentOrders, RecentOrdersSkeleton } from './RecentOrders';
import { Sidebar } from './Sidebar';

export default function DashboardPage() {
  return (
    <div className="dashboard">
      <Sidebar />
      <main>
        <Suspense fallback={<MetricsSkeleton />}>
          <MetricsCards />
        </Suspense>
        <Suspense fallback={<RecentOrdersSkeleton />}>
          <RecentOrders />
        </Suspense>
      </main>
    </div>
  );
}
```

`MetricsCards` and `RecentOrders` are async server components that fetch their own data. Each streams independently. `loading.tsx` in the route folder is the boundary for the whole page; use it for the initial navigation and nested `Suspense` for sections.

React Router v7 framework mode streams with `defer`-style promises returned from loaders and `<Await>` in the component.

## Server Component Boundaries

```tsx
// app/orders/page.tsx (server component)
import { Suspense } from 'react';

import { getCustomers, getOrders } from '@/lib/orders';

import { OrderFilters } from './OrderFilters';
import { OrderTable } from './OrderTable';

export default async function OrdersPage() {
  const [orders, customers] = await Promise.all([getOrders(), getCustomers()]);

  return (
    <OrderFilters customers={customers}>
      <Suspense fallback={<p role="status">Loading orders</p>}>
        <OrderTable orders={orders} />
      </Suspense>
    </OrderFilters>
  );
}
```

```tsx
// app/orders/OrderFilters.tsx
'use client';

import { useState, type ReactNode } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';

import type { Customer } from '@acme/customers-repository';

interface OrderFiltersProps {
  customers: readonly Customer[];
  children: ReactNode;
}

export function OrderFilters({ customers, children }: OrderFiltersProps) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [customerId, setCustomerId] = useState(searchParams.get('customer') ?? '');

  function apply(next: string) {
    setCustomerId(next);
    const params = new URLSearchParams(searchParams);
    if (next) params.set('customer', next);
    else params.delete('customer');
    router.push(`?${params.toString()}`);
  }

  return (
    <section>
      <label htmlFor="customer">Customer</label>
      <select id="customer" value={customerId} onChange={(event) => apply(event.target.value)}>
        <option value="">All</option>
        {customers.map((customer) => (
          <option key={customer.id} value={customer.id}>{customer.name}</option>
        ))}
      </select>
      {children}
    </section>
  );
}
```

The client component owns the interactive `<select>` and receives the server-rendered `<OrderTable>` as `children`. The table's markup never ships as JavaScript.

| Boundary decision                                          | Server                       | Client                           |
| ---------------------------------------------------------- | ---------------------------- | -------------------------------- |
| Reads a database, secret, or filesystem                    | Yes                          | Never                            |
| Uses `useState`, `useEffect`, event handlers               | No                           | Yes                              |
| Renders a large dependency (markdown, syntax highlighting) | Yes, keeps it off the client | Only if it must react to input   |
| Third-party component that needs `window`                  | No                           | `next/dynamic` with `ssr: false` |

## Images

| Context    | Rule                                                                                                         |
| ---------- | ------------------------------------------------------------------------------------------------------------ |
| Next       | `<Image src width height sizes>`; `priority` on the LCP image; `fill` with a sized parent for responsive art |
| Vite       | `<img width height srcset sizes loading="lazy" decoding="async">`; `fetchpriority="high"` on the LCP image   |
| Formats    | AVIF then WebP with a JPEG fallback via `<picture>`; Next handles this automatically                         |
| Above fold | Never `loading="lazy"`; preload with `<link rel="preload" as="image" imagesrcset imagesizes>` when critical  |
| Layout     | Always reserve space: intrinsic `width`/`height` or CSS `aspect-ratio`                                       |

```tsx
// Vite: responsive product image below the fold
<img
  src="/products/lamp-640.avif"
  srcSet="/products/lamp-320.avif 320w, /products/lamp-640.avif 640w, /products/lamp-1280.avif 1280w"
  sizes="(min-width: 768px) 320px, 100vw"
  width={640}
  height={480}
  alt="Desk lamp"
  loading="lazy"
  decoding="async"
/>
```

```tsx
// Next: LCP hero image
import Image from 'next/image';

import hero from '@/assets/hero.jpg';

<Image src={hero} alt="" priority sizes="100vw" placeholder="blur" />
```

## Preloading Assets

```tsx
// Vite: index.html
<link rel="preload" as="font" href="/fonts/inter-var.woff2" type="font/woff2" crossorigin>
<link rel="preload" as="image" href="/hero-1280.avif" imagesrcset="/hero-640.avif 640w, /hero-1280.avif 1280w" imagesizes="100vw" fetchpriority="high">
```

```tsx
// Next: app/layout.tsx
import { Inter } from 'next/font/google';

const inter = Inter({ subsets: ['latin'], display: 'swap' });

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={inter.className}>
      <body>{children}</body>
    </html>
  );
}
```

React 19 also exposes `preload` and `preinit` from `react-dom` for resources discovered during render:

```ts
import { preload } from 'react-dom';

preload('/fonts/inter-var.woff2', { as: 'font', type: 'font/woff2', crossOrigin: 'anonymous' });
```

## Testing Loaders

```ts
// src/features/orders/routes/OrderDetailRoute.test.ts
// @vitest-environment node
import { describe, expect, it } from 'vitest';

import { queryClient } from '@/app/queryClient';
import { orderQueries } from '@/features/orders/api/queries';

import { loader } from './OrderDetailRoute';

describe('OrderDetailRoute loader', () => {
  it('populates the order query cache when orderId is valid', async () => {
    await loader({ params: { orderId: '1001' }, request: new Request('http://localhost/orders/1001'), context: {} });

    expect(queryClient.getQueryData(orderQueries.detail('1001').queryKey)).toMatchObject({ id: '1001' });
  });

  it('throws a 404 response when orderId is missing', async () => {
    await expect(
      loader({ params: {}, request: new Request('http://localhost/orders/'), context: {} }),
    ).rejects.toMatchObject({ status: 404 });
  });
});
```

The `msw` server from the testing skill runs in `node` environment tests too, so the loader hits the same default handlers.
