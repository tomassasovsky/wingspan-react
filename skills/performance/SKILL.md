---
name: react-performance
description: Best practices for React rendering and loading performance, covering measurement with the React DevTools Profiler, Lighthouse, and web-vitals, the React Compiler and memoization, code splitting with React.lazy and Suspense, list virtualization with @tanstack/react-virtual, image loading, request waterfalls, bundle analysis, Next.js server component boundaries, and useTransition or useDeferredValue. Use when profiling slow renders, reducing bundle size, improving LCP, INP, or CLS, adding memo, useMemo, or useCallback, virtualizing long lists, or reviewing code for performance issues.
argument-hint: "[file-or-directory]"
allowed-tools: Read Glob Grep Bash
---

# React Performance

Performance fundamentals for React apps: measure first, ship less JavaScript, avoid waterfalls, render only what changed, and keep interactions under the INP budget.

---

## Core Standards

Apply these standards to ALL performance work:

- **Measure before optimizing** — every optimization cites a React DevTools Profiler recording, a Lighthouse report, or a `web-vitals` metric taken before and after
- **Use the React Compiler when available** — enable `babel-plugin-react-compiler` (Vite) or `reactCompiler: true` (Next); with the compiler on, never add manual `memo`, `useMemo`, or `useCallback`
- **Without the compiler, memoize only with a measured cause** — `memo`/`useMemo`/`useCallback` require a Profiler recording showing the re-render or computation cost
- **Code-split at route boundaries** — `route.lazy` (React Router) or file-system routes (Next); `React.lazy` + `Suspense` for heavy below-route components
- **Virtualize lists over ~100 rows** — `@tanstack/react-virtual`; never render thousands of DOM nodes
- **Images declare dimensions and load lazily** — Next `<Image>` with `sizes`; otherwise `width`, `height`, `loading="lazy"`, `decoding="async"`, and `srcset`; the LCP image is never lazy
- **Avoid request waterfalls** — prefetch in route loaders, fetch in parallel with `useSuspenseQueries`, hoist data requirements to the route
- **Keep state local** — state lives in the lowest component that needs it; lift only when two subtrees share it
- **No inline object, array, or function props on memoized children** — hoist constants to module scope or memoize them
- **Analyze the bundle on every dependency change** — `rollup-plugin-visualizer` (Vite) or `@next/bundle-analyzer` (Next); no library over 50 kB gzip without a recorded justification
- **Server components by default in Next** — `'use client'` only at interactive leaves; server components pass data down as props or `children`
- **Mark expensive updates as non-urgent** — `useTransition` for state changes that render large trees; `useDeferredValue` for values that feed expensive children
- **Ship to Web Vitals targets** — LCP under 2.5 s, INP under 200 ms, CLS under 0.1 at the 75th percentile on real users

---

## Web Vitals Targets

| Metric | Good      | Needs improvement | Poor     | Typical cause in React apps                                            |
| ------ | --------- | ----------------- | -------- | ---------------------------------------------------------------------- |
| LCP    | <= 2.5 s  | 2.5 s to 4.0 s    | > 4.0 s  | Lazy-loaded hero image, client-side fetch before first paint           |
| INP    | <= 200 ms | 200 ms to 500 ms  | > 500 ms | Synchronous re-render of large trees on input, unvirtualized lists     |
| CLS    | <= 0.1    | 0.1 to 0.25       | > 0.25   | Images without dimensions, late fonts, content injected above the fold |
| TTFB   | <= 0.8 s  | 0.8 s to 1.8 s    | > 1.8 s  | Slow server data fetch, no streaming, uncached server component calls  |

Targets are measured at p75 with `web-vitals` on production traffic, not on a developer laptop.

---

## Symptom to Tool to Fix

| Symptom                                   | Measure with                            | Fix                                                                 |
| ----------------------------------------- | --------------------------------------- | ------------------------------------------------------------------- |
| Typing lags in a search box               | Profiler: commits per keystroke         | `useDeferredValue` on the query; memoize the results component      |
| Tab switch freezes the UI                 | Profiler: long commit on tab state      | `useTransition` around `setTab`                                     |
| Scroll stutters on a long list            | Performance panel: long tasks on scroll | `@tanstack/react-virtual`                                           |
| Whole page re-renders on unrelated change | Profiler: "why did this render"         | Split context, colocate state, `children` pattern                   |
| First load downloads one huge chunk       | Bundle visualizer                       | Route-level `lazy`, `React.lazy` for heavy widgets, replace library |
| Page waits for request A, then B, then C  | Network panel: staggered start times    | Prefetch in loader, `useSuspenseQueries`, hoist to parent route     |
| LCP is a hero image                       | Lighthouse: LCP element                 | `priority`/`fetchpriority="high"`, preload, correct `sizes`         |
| Layout shifts as data arrives             | Lighthouse: CLS sources                 | Reserve space with skeletons and `aspect-ratio`; image dimensions   |

---

## Lazy Routes with Suspense

React Router v7 data routes split each route module, including its loader, into its own chunk.

```tsx
// src/app/router.tsx
import { createBrowserRouter } from 'react-router';

import { RootLayout } from '@/app/RootLayout';
import { RouteErrorBoundary } from '@/app/RouteErrorBoundary';

export const router = createBrowserRouter([
  {
    path: '/',
    Component: RootLayout,
    ErrorBoundary: RouteErrorBoundary,
    children: [
      { index: true, lazy: () => import('@/features/home/routes/HomeRoute') },
      { path: 'orders', lazy: () => import('@/features/orders/routes/OrdersRoute') },
      { path: 'orders/:orderId', lazy: () => import('@/features/orders/routes/OrderDetailRoute') },
    ],
  },
]);
```

Each route module exports `Component` and `loader`; the loader prefetches queries so data and code load in parallel (see [references/loading.md](references/loading.md)).

Heavy components below a route (charts, editors, maps) use `React.lazy` with a `Suspense` boundary sized to the component so the rest of the page paints first.

```tsx
// src/features/reports/components/ReportChart.tsx
import { lazy, Suspense } from 'react';

import { ChartSkeleton } from '@acme/ui';

const RevenueChart = lazy(() =>
  import('./RevenueChart').then((module) => ({ default: module.RevenueChart })),
);

export function ReportChart({ reportId }: { reportId: string }) {
  return (
    <Suspense fallback={<ChartSkeleton height={320} />}>
      <RevenueChart reportId={reportId} />
    </Suspense>
  );
}
```

`lazy()` is called at module scope, never inside a component body. In Next, file-system routes split automatically; use `next/dynamic` for heavy client widgets.

---

## Virtualized List

```tsx
// src/features/orders/components/OrderList.tsx
import { useRef } from 'react';
import { useVirtualizer } from '@tanstack/react-virtual';

import type { Order } from '@acme/orders-repository';

interface OrderListProps {
  orders: readonly Order[];
  height: number;
  rowHeight?: number;
}

export function OrderList({ orders, height, rowHeight = 48 }: OrderListProps) {
  const parentRef = useRef<HTMLDivElement>(null);
  const virtualizer = useVirtualizer({
    count: orders.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => rowHeight,
    overscan: 8,
  });

  return (
    <div ref={parentRef} style={{ height, overflow: 'auto' }}>
      <ul role="list" aria-label="Orders" style={{ height: virtualizer.getTotalSize(), position: 'relative', margin: 0, padding: 0 }}>
        {virtualizer.getVirtualItems().map((row) => {
          const order = orders[row.index];
          if (!order) return null;
          return (
            <li
              key={order.id}
              style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: row.size, transform: `translateY(${row.start}px)` }}
            >
              <span>{order.customer}</span>
              <span>{order.total}</span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
```

Rows have a fixed height, so `measureElement` is not wired; enable it only for variable-height rows and measure the cost. The matching test is in [references/rendering.md](references/rendering.md).

---

## Deferred Search

`useDeferredValue` lets the input update immediately while the expensive results lag behind. It only helps when the results component is memoized (or compiled) so the urgent render skips it.

```tsx
// src/features/catalog/components/ProductSearch.tsx
import { memo, useDeferredValue, useState } from 'react';

import type { Product } from '@acme/catalog-repository';

import { filterProducts } from '../filterProducts';

interface ProductSearchProps {
  products: readonly Product[];
}

export function ProductSearch({ products }: ProductSearchProps) {
  const [query, setQuery] = useState('');
  const deferredQuery = useDeferredValue(query);
  const isStale = query !== deferredQuery;

  return (
    <>
      <label htmlFor="product-search">Search products</label>
      <input id="product-search" type="search" value={query} onChange={(event) => setQuery(event.target.value)} />
      <div aria-busy={isStale} style={{ opacity: isStale ? 0.6 : 1 }}>
        <SearchResults products={products} query={deferredQuery} />
      </div>
    </>
  );
}

const SearchResults = memo(function SearchResults({ products, query }: ProductSearchProps & { query: string }) {
  const matches = filterProducts(products, query);
  if (matches.length === 0) return <p>No products match</p>;
  return (
    <ul aria-label="Results">
      {matches.map((product) => (
        <li key={product.id}>{product.name}</li>
      ))}
    </ul>
  );
});
```

The matching test is in [references/rendering.md](references/rendering.md).

---

## Transition

`useTransition` marks a state update as interruptible so the click responds immediately and the heavy render happens in the background.

```tsx
// src/features/orders/components/OrderTabs.tsx
import { useState, useTransition } from 'react';

import { ArchivedOrders } from './ArchivedOrders';
import { OpenOrders } from './OpenOrders';

const TABS = ['open', 'archived'] as const;
type Tab = (typeof TABS)[number];

const LABELS: Record<Tab, string> = { open: 'Open', archived: 'Archived' };

export function OrderTabs() {
  const [tab, setTab] = useState<Tab>('open');
  const [isPending, startTransition] = useTransition();

  return (
    <div>
      <div role="tablist" aria-label="Order views">
        {TABS.map((candidate) => (
          <button
            key={candidate}
            type="button"
            role="tab"
            id={`tab-${candidate}`}
            aria-selected={tab === candidate}
            aria-controls="orders-panel"
            onClick={() => startTransition(() => setTab(candidate))}
          >
            {LABELS[candidate]}
          </button>
        ))}
      </div>
      <div id="orders-panel" role="tabpanel" aria-labelledby={`tab-${tab}`} aria-busy={isPending}>
        {tab === 'open' ? <OpenOrders /> : <ArchivedOrders />}
      </div>
    </div>
  );
}
```

React 19 also accepts async functions in `startTransition` for form actions and mutations: `startTransition(async () => { await archiveOrder(id); })`. The matching test is in [references/rendering.md](references/rendering.md).

---

## Memoization Decision Table

| Situation                                              | React Compiler on | React Compiler off                                  |
| ------------------------------------------------------ | ----------------- | --------------------------------------------------- |
| Child re-renders with identical props (Profiler shows) | Nothing           | `memo(Child)`                                       |
| Derivation costs > 1 ms per render (Profiler shows)    | Nothing           | `useMemo`                                           |
| Callback passed to a memoized child                    | Nothing           | `useCallback`                                       |
| Object or array literal passed to a memoized child     | Nothing           | `useMemo`, or hoist to module scope if constant     |
| Value used as an effect dependency                     | Nothing           | `useMemo`/`useCallback` so the effect does not loop |
| Cheap component, no measurement                        | Nothing           | Nothing                                             |

Enable the compiler and its lint rules per [references/rendering.md](references/rendering.md).

---

## Server Component Boundaries (Next)

| Rule                                                                       | Why                                               |
| -------------------------------------------------------------------------- | ------------------------------------------------- |
| Pages, layouts, and data-fetching components stay on the server            | Zero client JS for markup that never changes      |
| `'use client'` only on components that use state, effects, or browser APIs | Each directive is a bundle entry point            |
| Pass server-rendered content into client components as `children`          | Keeps the client boundary at the interactive leaf |
| Fetch in parallel with `Promise.all` in server components                  | Sequential `await` is a waterfall                 |
| Stream slow sections with `<Suspense>` and `loading.tsx`                   | TTFB and LCP do not wait for the slowest query    |
| `next/dynamic` with `ssr: false` for browser-only libraries                | Avoids shipping and executing them on the server  |

A complete page with a client filter wrapping a server-rendered table is in [references/loading.md](references/loading.md).

---

## Images and Bundles

| Concern      | Rule                                                                                                         |
| ------------ | ------------------------------------------------------------------------------------------------------------ |
| Next images  | `<Image src width height sizes>`; `priority` on the LCP image; `fill` with a sized parent for responsive art |
| Vite images  | `<img width height srcset sizes loading="lazy" decoding="async">`; `fetchpriority="high"` on the LCP image   |
| Layout       | Always reserve space: intrinsic `width`/`height` or CSS `aspect-ratio`                                       |
| Bundle audit | `ANALYZE=true pnpm build` after every dependency change; `size-limit` budget enforced in CI                  |
| Imports      | `lodash-es/debounce`, `date-fns/format`, or ESM-only libraries so tree shaking works                         |

Analyzer configuration and size budgets are in [references/measuring.md](references/measuring.md).

---

## Anti-Patterns

| Anti-Pattern                                       | Problem                                                  | Correct Approach                                                |
| -------------------------------------------------- | -------------------------------------------------------- | --------------------------------------------------------------- |
| `memo`/`useMemo`/`useCallback` everywhere          | Cost with no measured benefit; hides real hot spots      | Profile first; enable the React Compiler                        |
| `<Child options={{ a: 1 }} />` on a memoized child | New object each render defeats `memo`                    | Hoist constant to module scope or `useMemo`                     |
| One context holding the whole app state            | Every consumer re-renders on any change                  | Split by update frequency; `zustand` selectors for shared state |
| Fetching in `useEffect` inside nested components   | Request waterfall as each level mounts                   | Route loader prefetch; `useSuspenseQueries` at the parent       |
| Rendering 5,000 rows with `.map`                   | Slow commit, slow scroll, high memory                    | `@tanstack/react-virtual`                                       |
| `lazy(() => import(...))` inside a component       | New component type each render; remounts and loses state | Call `lazy` at module scope                                     |
| `loading="lazy"` on the hero image                 | Delays LCP                                               | `priority` / `fetchpriority="high"` and preload                 |
| `<img>` without `width`/`height`                   | Layout shift when the image loads                        | Intrinsic dimensions or `aspect-ratio`                          |
| `import { debounce } from 'lodash'`                | Pulls the whole library into the bundle                  | `lodash-es/debounce` or a native implementation                 |
| `'use client'` on a page or layout                 | Entire subtree ships to the client                       | Move the directive to the interactive leaf                      |
| `key={index}` on reorderable lists                 | Wrong DOM reuse; state attaches to the wrong item        | Stable ids as keys                                              |
| Deriving state in `useEffect` + `setState`         | Extra render per change; cascading updates               | Compute during render; `useMemo` only when measured             |
| Optimizing on a developer machine only             | Real users are on slower devices and networks            | `web-vitals` field data at p75; Lighthouse with CPU throttling  |

---

## Additional Resources

- [references/rendering.md](references/rendering.md) — why components re-render, React Compiler setup, context splitting, the `children` pattern, keys, state colocation, and tests for the examples above
- [references/loading.md](references/loading.md) — diagnosing waterfalls, prefetching with loaders and `Link`, `useSuspenseQueries`, streaming, server component boundaries, and image loading
- [references/measuring.md](references/measuring.md) — React DevTools Profiler workflow, `<Profiler>` API, `web-vitals` reporting, Lighthouse CI, and bundle analysis
- [references/anti-patterns.md](references/anti-patterns.md) — before/after code for the most common performance mistakes
