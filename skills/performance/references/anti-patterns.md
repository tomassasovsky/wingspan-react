# Anti-Patterns

Each entry shows the mistake, the observable symptom, and the corrected code.

## Memoizing Without Measuring

Symptom: code is harder to read, `useCallback` dependency bugs appear, and the Profiler shows no change.

```tsx
// Before
export function Toolbar({ onSave }: { onSave: () => void }) {
  const label = useMemo(() => 'Save', []);
  const handleClick = useCallback(() => onSave(), [onSave]);
  return <button type="button" onClick={handleClick}>{label}</button>;
}
```

```tsx
// After
export function Toolbar({ onSave }: { onSave: () => void }) {
  return <button type="button" onClick={onSave}>Save</button>;
}
```

Memoization is justified by a Profiler recording, or removed. With the React Compiler enabled, manual memoization is deleted.

## Inline Props Defeating `memo`

Symptom: a `memo` child still re-renders on every parent render; Profiler says "Props changed: (style, onSelect)".

```tsx
// Before
<OrderRow order={order} style={{ height: 48 }} onSelect={(id) => setSelected(id)} />
```

```tsx
// After
const ROW_STYLE = { height: 48 } as const;

const handleSelect = useCallback((id: string) => setSelected(id), []);

<OrderRow order={order} style={ROW_STYLE} onSelect={handleSelect} />
```

## One Context for Everything

Symptom: typing in a search box re-renders the navigation, sidebar, and footer.

```tsx
// Before
const AppContext = createContext<{ user: User; searchQuery: string; setSearchQuery: (q: string) => void } | null>(null);
```

```tsx
// After: high-frequency state stays local to the search feature; shared state moves to a zustand store with selectors.
import { create } from 'zustand';

interface SearchStore {
  query: string;
  setQuery: (query: string) => void;
}

export const useSearchStore = create<SearchStore>((set) => ({
  query: '',
  setQuery: (query) => set({ query }),
}));

// Consumers subscribe to one slice; only they re-render.
const query = useSearchStore((state) => state.query);
```

## Fetching in Nested Effects

Symptom: Network panel shows request B starting only after request A completes and the child mounts.

```tsx
// Before
function OrderPage({ orderId }: { orderId: string }) {
  const { data: order } = useQuery(orderQueries.detail(orderId));
  if (!order) return <Spinner />;
  return <CustomerPanel customerId={order.customerId} />; // fetches on mount
}
```

```tsx
// After: the loader starts both before render; the component reads them in parallel.
export async function loader({ params }: LoaderFunctionArgs) {
  const orderId = params['orderId'] ?? '';
  const order = await queryClient.ensureQueryData(orderQueries.detail(orderId));
  void queryClient.prefetchQuery(customerQueries.detail(order.customerId));
  return null;
}
```

## Unvirtualized Long Lists

Symptom: Performance panel shows a 400 ms commit on mount and long tasks on every scroll frame.

```tsx
// Before
<ul>{orders.map((order) => <OrderRow key={order.id} order={order} />)}</ul>
```

```tsx
// After: see the OrderList example in SKILL.md
const virtualizer = useVirtualizer({ count: orders.length, getScrollElement: () => parentRef.current, estimateSize: () => 48 });
```

## `lazy` Inside a Component

Symptom: a lazy component remounts and refetches on every parent render; its state resets.

```tsx
// Before
export function ReportPage() {
  const Chart = lazy(() => import('./Chart'));
  return <Suspense fallback={null}><Chart /></Suspense>;
}
```

```tsx
// After
const Chart = lazy(() => import('./Chart'));

export function ReportPage() {
  return <Suspense fallback={<ChartSkeleton />}><Chart /></Suspense>;
}
```

## Lazy-Loading the LCP Image

Symptom: Lighthouse reports the hero image as the LCP element with "Lazy-loaded LCP image".

```tsx
// Before
<img src="/hero.jpg" alt="" loading="lazy" />
```

```tsx
// After (Vite)
<img src="/hero-1280.avif" srcSet="/hero-640.avif 640w, /hero-1280.avif 1280w" sizes="100vw" width={1280} height={720} alt="" fetchPriority="high" decoding="async" />

// After (Next)
<Image src={hero} alt="" priority sizes="100vw" />
```

## Images Without Dimensions

Symptom: CLS above 0.1; content jumps as images load.

```tsx
// Before
<img src={product.imageUrl} alt={product.name} />
```

```tsx
// After
<img src={product.imageUrl} alt={product.name} width={320} height={240} loading="lazy" decoding="async" style={{ aspectRatio: '4 / 3' }} />
```

## Whole-Library Imports

Symptom: the bundle treemap shows `lodash` or `@mui/icons-material` occupying hundreds of kilobytes.

```ts
// Before
import { debounce } from 'lodash';
import * as Icons from '@mui/icons-material';
```

```ts
// After
import debounce from 'lodash-es/debounce';
import SearchIcon from '@mui/icons-material/Search';
```

Use ESM-only libraries with `"sideEffects": false` so tree shaking removes unused exports.

## `'use client'` at the Page Level

Symptom: Next bundle analyzer shows the page's entire tree, including markdown rendering and data formatting, in the client bundle.

```tsx
// Before: app/orders/page.tsx
'use client';

export default function OrdersPage() {
  const [filter, setFilter] = useState('');
  return (
    <>
      <input value={filter} onChange={(event) => setFilter(event.target.value)} />
      <OrderTable filter={filter} />   {/* renders markdown, formats currency, huge */}
    </>
  );
}
```

```tsx
// After: the page stays on the server; the input is a client leaf that writes to the URL.
export default async function OrdersPage({ searchParams }: { searchParams: Promise<{ filter?: string }> }) {
  const { filter = '' } = await searchParams;
  const orders = await getOrders({ filter });
  return (
    <>
      <FilterInput initialValue={filter} />   {/* 'use client', pushes ?filter= */}
      <OrderTable orders={orders} />
    </>
  );
}
```

## Index Keys on Reorderable Lists

Symptom: deleting the first item leaves the wrong row's input value in place; animations attach to the wrong element.

```tsx
// Before
{items.map((item, index) => <ItemEditor key={index} item={item} />)}
```

```tsx
// After
{items.map((item) => <ItemEditor key={item.id} item={item} />)}
```

## Derived State in Effects

Symptom: two renders per change; a flash of stale derived values; Profiler shows cascading updates.

```tsx
// Before
const [total, setTotal] = useState(0);
useEffect(() => {
  setTotal(items.reduce((sum, item) => sum + item.price, 0));
}, [items]);
```

```tsx
// After
const total = items.reduce((sum, item) => sum + item.price, 0);
```

Wrap in `useMemo` only when the Profiler shows the reduction is expensive.

## Synchronous Heavy Updates on Input

Symptom: INP above 200 ms while typing; each keystroke waits for the results list to render.

```tsx
// Before
const [query, setQuery] = useState('');
<input value={query} onChange={(event) => setQuery(event.target.value)} />
<Results query={query} />
```

```tsx
// After
const [query, setQuery] = useState('');
const deferredQuery = useDeferredValue(query);
<input value={query} onChange={(event) => setQuery(event.target.value)} />
<Results query={deferredQuery} />   {/* Results is memo'd or compiled */}
```

## Reading Layout During Render

Symptom: forced synchronous layout warnings in the Performance panel; jank during scroll.

```tsx
// Before
function Sticky() {
  const top = document.querySelector('header')?.getBoundingClientRect().height ?? 0; // during render
  return <div style={{ top }} />;
}
```

```tsx
// After
function Sticky() {
  const [top, setTop] = useState(0);
  useLayoutEffect(() => {
    const header = document.querySelector('header');
    if (!header) return;
    const observer = new ResizeObserver(([entry]) => setTop(entry?.contentRect.height ?? 0));
    observer.observe(header);
    return () => observer.disconnect();
  }, []);
  return <div style={{ top }} />;
}
```

Better still: reserve the header height with a CSS custom property and avoid measuring at all.

## Serialized Dependencies

Symptom: an effect re-runs on every render; `JSON.stringify` shows up in the Profiler.

```tsx
// Before
useEffect(() => {
  void refetch();
}, [JSON.stringify(filters)]);
```

```tsx
// After: primitives in the dependency array, or a stable reference from the URL or a store.
const { status, customerId } = filters;
useEffect(() => {
  void refetch();
}, [status, customerId, refetch]);
```

With `@tanstack/react-query`, put `filters` in the query key instead and drop the effect entirely.

## Optimizing on a Fast Machine

Symptom: Lighthouse scores 98 locally; field INP at p75 is 450 ms on Android.

| Do                                                      | Not                          |
| ------------------------------------------------------- | ---------------------------- |
| Profile with CPU throttling 4x and "Fast 3G"            | Unthrottled desktop only     |
| Read `web-vitals` p75 per route from production         | Site-wide averages           |
| Test on a mid-range Android device or emulation         | Latest MacBook only          |
| Enforce Lighthouse CI and `size-limit` on pull requests | Manual audits before release |
