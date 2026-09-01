# Measuring

No optimization lands without a before and after number. Pick the tool by the question.

| Question                                   | Tool                                                | Output                                           |
| ------------------------------------------ | --------------------------------------------------- | ------------------------------------------------ |
| Which components render, how long, and why | React DevTools Profiler                             | Flame graph, ranked chart, "why did this render" |
| Is a specific subtree slow in production   | `<Profiler>` component                              | `actualDuration` per commit sent to analytics    |
| What do real users experience              | `web-vitals` field data                             | LCP, INP, CLS, TTFB at p75                       |
| Lab score and audit list for a page        | Lighthouse / Lighthouse CI                          | Scores, opportunities, diagnostics               |
| What is blocking the main thread           | Chrome Performance panel                            | Long tasks, layout, script evaluation            |
| What is in the bundle                      | `rollup-plugin-visualizer`, `@next/bundle-analyzer` | Treemap per chunk                                |

## React DevTools Profiler

1. Open the Profiler tab and enable "Record why each component rendered while profiling" in settings.
2. Click record, perform one interaction (one keystroke, one click), stop.
3. Read the ranked chart: the widest bar is the most expensive component in that commit.
4. Select a component: the right panel lists the render cause and props that changed.
5. Fix, re-record the same interaction, compare commit durations.

Profile a production build (`pnpm build && pnpm preview`) with the `react-dom/profiling` alias when development-mode overhead distorts numbers:

```ts
// vite.config.ts (profiling build only)
resolve: {
  alias: process.env['PROFILE'] ? { 'react-dom/client': 'react-dom/profiling' } : {},
},
```

Turn on "Highlight updates when components render" in the Components tab to see re-render storms during scrolling or typing without recording.

## `<Profiler>` Component

Wrap a subtree to record commit timings programmatically. Use it for a known-heavy region, not the whole app.

```tsx
// src/app/performance/RenderProfiler.tsx
import { Profiler, type ProfilerOnRenderCallback, type ReactNode } from 'react';

import { track } from '@acme/analytics';

const SLOW_COMMIT_MS = 16;

const onRender: ProfilerOnRenderCallback = (id, phase, actualDuration) => {
  if (actualDuration < SLOW_COMMIT_MS) return;
  track('slow_render', { id, phase, duration: Math.round(actualDuration) });
};

export function RenderProfiler({ id, children }: { id: string; children: ReactNode }) {
  return (
    <Profiler id={id} onRender={onRender}>
      {children}
    </Profiler>
  );
}
```

```tsx
// src/app/performance/RenderProfiler.test.tsx
import { screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { track } from '@acme/analytics';
import { renderWithProviders } from '@/test/render';

import { RenderProfiler } from './RenderProfiler';

vi.mock('@acme/analytics', () => ({ track: vi.fn() }));

describe('RenderProfiler', () => {
  it('renders children', () => {
    renderWithProviders(
      <RenderProfiler id="orders">
        <p>Orders</p>
      </RenderProfiler>,
    );

    expect(screen.getByText('Orders')).toBeInTheDocument();
  });

  it('does not track fast commits', () => {
    renderWithProviders(
      <RenderProfiler id="orders">
        <p>Orders</p>
      </RenderProfiler>,
    );

    expect(vi.mocked(track)).not.toHaveBeenCalled();
  });
});
```

`<Profiler>` is stripped from production builds unless the profiling bundle is used; ship it only behind the `react-dom/profiling` alias.

## `web-vitals` Field Data

```ts
// src/app/performance/reportWebVitals.ts
import { onCLS, onINP, onLCP, onTTFB, type Metric } from 'web-vitals';

export interface VitalsPayload {
  name: Metric['name'];
  value: number;
  rating: Metric['rating'];
  id: string;
  navigationType: Metric['navigationType'];
  path: string;
}

export function reportWebVitals(send: (payload: VitalsPayload) => void, path = window.location.pathname): void {
  const handle = (metric: Metric) => {
    send({
      name: metric.name,
      value: Math.round(metric.name === 'CLS' ? metric.value * 1000 : metric.value),
      rating: metric.rating,
      id: metric.id,
      navigationType: metric.navigationType,
      path,
    });
  };

  onCLS(handle);
  onINP(handle);
  onLCP(handle);
  onTTFB(handle);
}

export function sendToAnalytics(payload: VitalsPayload): void {
  const body = JSON.stringify(payload);
  if (navigator.sendBeacon) {
    navigator.sendBeacon('/api/vitals', body);
    return;
  }
  void fetch('/api/vitals', { body, method: 'POST', keepalive: true, headers: { 'Content-Type': 'application/json' } });
}
```

```ts
// src/main.tsx (after render)
import { reportWebVitals, sendToAnalytics } from '@/app/performance/reportWebVitals';

reportWebVitals(sendToAnalytics);
```

```ts
// src/app/performance/reportWebVitals.test.ts
import { describe, expect, it, vi } from 'vitest';
import type { Metric } from 'web-vitals';

import { reportWebVitals } from './reportWebVitals';

const listeners: Array<(metric: Metric) => void> = [];

vi.mock('web-vitals', () => {
  const register = (callback: (metric: Metric) => void) => {
    listeners.push(callback);
  };
  return { onCLS: register, onINP: register, onLCP: register, onTTFB: register };
});

function emit(metric: Partial<Metric> & Pick<Metric, 'name' | 'value'>): void {
  const full = { rating: 'good', id: 'v1', navigationType: 'navigate', delta: 0, entries: [], ...metric } as Metric;
  for (const listener of listeners) listener(full);
}

describe('reportWebVitals', () => {
  it('sends LCP rounded to milliseconds with the current path', () => {
    const send = vi.fn();
    reportWebVitals(send, '/orders');

    emit({ name: 'LCP', value: 1234.56 });

    expect(send).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'LCP', value: 1235, path: '/orders', rating: 'good' }),
    );
  });

  it('scales CLS by 1000 so it is reported as an integer', () => {
    const send = vi.fn();
    reportWebVitals(send, '/orders');

    emit({ name: 'CLS', value: 0.0523 });

    expect(send).toHaveBeenCalledWith(expect.objectContaining({ name: 'CLS', value: 52 }));
  });
});
```

Next apps use `useReportWebVitals` from `next/web-vitals` in a client component mounted in the root layout and forward to the same `sendToAnalytics`.

Dashboards alert on p75 crossing the "needs improvement" threshold per route; a single slow page hidden inside a site-wide average is the common failure.

## Lighthouse CI

```json
// lighthouserc.json
{
  "ci": {
    "collect": {
      "startServerCommand": "pnpm preview --port 4173",
      "startServerReadyPattern": "Local:",
      "url": ["http://localhost:4173/", "http://localhost:4173/orders", "http://localhost:4173/orders/1001"],
      "numberOfRuns": 3,
      "settings": {
        "preset": "desktop",
        "throttlingMethod": "simulate"
      }
    },
    "assert": {
      "preset": "lighthouse:no-pwa",
      "assertions": {
        "categories:performance": ["error", { "minScore": 0.9 }],
        "categories:accessibility": ["error", { "minScore": 0.95 }],
        "largest-contentful-paint": ["error", { "maxNumericValue": 2500 }],
        "cumulative-layout-shift": ["error", { "maxNumericValue": 0.1 }],
        "total-blocking-time": ["error", { "maxNumericValue": 300 }],
        "unused-javascript": ["warn", { "maxNumericValue": 150000 }],
        "uses-responsive-images": "warn"
      }
    },
    "upload": {
      "target": "temporary-public-storage"
    }
  }
}
```

```yaml
# .github/workflows/lighthouse.yml
name: lighthouse

on:
  pull_request:

jobs:
  lhci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm --filter web build
      - run: pnpm dlx @lhci/cli@0.14.x autorun --config=apps/web/lighthouserc.json
```

Lighthouse lab numbers use simulated throttling; a passing CI run does not replace field data. Total Blocking Time is the lab proxy for INP.

## Chrome Performance Panel

Record with CPU throttling at 4x and "Web Vitals" lane enabled. Read the timeline for:

| Track         | Look for                                                    | Maps to       |
| ------------- | ----------------------------------------------------------- | ------------- |
| Main          | Long tasks (> 50 ms, red corner)                            | INP, TBT      |
| Interactions  | Input delay, processing, presentation delay per interaction | INP breakdown |
| Network       | Gaps between dependent requests                             | Waterfalls    |
| Layout shifts | Purple markers with the shifted element                     | CLS           |
| Timings       | LCP marker and its element                                  | LCP           |

Use `performance.mark` and `performance.measure` around suspicious application code so the marks appear in the Timings track:

```ts
performance.mark('filter-start');
const matches = filterProducts(products, query);
performance.mark('filter-end');
performance.measure('filter-products', 'filter-start', 'filter-end');
```

## Bundle Analysis

```ts
// vite.config.ts
import { visualizer } from 'rollup-plugin-visualizer';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [
    // ...
    process.env['ANALYZE']
      ? visualizer({ filename: 'dist/stats.html', gzipSize: true, brotliSize: true, open: true })
      : undefined,
  ],
});
```

```ts
// next.config.ts
import bundleAnalyzer from '@next/bundle-analyzer';
import type { NextConfig } from 'next';

const withBundleAnalyzer = bundleAnalyzer({ enabled: process.env['ANALYZE'] === 'true' });

const nextConfig: NextConfig = { reactCompiler: true };

export default withBundleAnalyzer(nextConfig);
```

```json
// package.json (size budget enforced in CI)
{
  "size-limit": [
    { "path": "dist/assets/index-*.js", "limit": "180 kB", "gzip": true },
    { "path": "dist/assets/vendor-*.js", "limit": "120 kB", "gzip": true }
  ]
}
```

Run `ANALYZE=true pnpm build` after adding a dependency and `pnpm dlx size-limit` in CI so budgets fail the pull request, not the release.
