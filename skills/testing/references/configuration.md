# Configuration

## Packages

| Package                       | Purpose                                            | Dev dependency? |
| ----------------------------- | -------------------------------------------------- | --------------- |
| `vitest`                      | Test runner, assertions, mocks, coverage CLI       | Yes             |
| `@vitest/coverage-v8`         | V8 coverage provider                               | Yes             |
| `@testing-library/react`      | `render`, `renderHook`, `screen`, `waitFor`        | Yes             |
| `@testing-library/dom`        | Peer dependency of `@testing-library/react` v16+   | Yes             |
| `@testing-library/user-event` | Realistic user interactions                        | Yes             |
| `@testing-library/jest-dom`   | DOM matchers (`toBeInTheDocument`, `toBeDisabled`) | Yes             |
| `jsdom` or `happy-dom`        | DOM environment for component tests                | Yes             |
| `msw`                         | Network mocking in node and browser                | Yes             |
| `@playwright/test`            | End-to-end runner and browsers                     | Yes             |
| `vitest-axe`                  | Accessibility assertions in component tests        | Yes             |
| `@axe-core/playwright`        | Accessibility assertions in end-to-end tests       | Yes             |

```bash
pnpm add -D vitest @vitest/coverage-v8 jsdom @testing-library/react @testing-library/dom \
  @testing-library/user-event @testing-library/jest-dom msw @playwright/test vitest-axe
pnpm exec playwright install --with-deps
```

## `vitest.config.ts` (Vite app or package)

```ts
// vitest.config.ts
import { defineConfig, mergeConfig } from 'vitest/config';

import viteConfig from './vite.config';

export default mergeConfig(
  viteConfig,
  defineConfig({
    test: {
      environment: 'jsdom',
      globals: false,
      setupFiles: ['./src/test/setup.ts'],
      include: ['src/**/*.test.{ts,tsx}'],
      exclude: ['node_modules', 'dist', 'e2e'],
      css: false,
      clearMocks: true,
      restoreMocks: true,
      unstubEnvs: true,
      unstubGlobals: true,
      testTimeout: 10_000,
      sequence: { shuffle: true },
      reporters: process.env['CI'] ? ['default', 'junit'] : ['default'],
      outputFile: { junit: './reports/junit.xml' },
      coverage: {
        provider: 'v8',
        reporter: ['text', 'lcov', 'html'],
        reportsDirectory: './coverage',
        include: ['src/**/*.{ts,tsx}'],
        exclude: [
          'src/**/*.test.{ts,tsx}',
          'src/**/*.stories.tsx',
          'src/**/*.d.ts',
          'src/**/index.ts',
          'src/test/**',
          'src/main.tsx',
          'src/**/generated/**',
        ],
        thresholds: {
          lines: 100,
          functions: 100,
          branches: 100,
          statements: 100,
        },
      },
    },
  }),
);
```

`mergeConfig` reuses the app's `vite.config.ts` so `@vitejs/plugin-react`, `vite-tsconfig-paths`, and `@/` aliases apply to tests without duplication.

`sequence.shuffle` randomizes test order and exposes hidden coupling between tests.

## Environment Selection

| Environment | Use for                                   | Notes                                                      |
| ----------- | ----------------------------------------- | ---------------------------------------------------------- |
| `jsdom`     | Default for component tests               | Most complete DOM implementation; slower startup           |
| `happy-dom` | Large suites where startup time dominates | Faster; verify portals, `ResizeObserver`, and `matchMedia` |
| `node`      | Repositories, clients, schemas, stores    | No DOM; fastest                                            |

Override per file with a directive on line 1:

```ts
// @vitest-environment node
```

Packages with no components (`packages/*-api-client`, `packages/*-repository`) set `environment: 'node'` in their own config.

## Monorepo Projects

Root config discovers every workspace config so `pnpm vitest` runs everything and coverage merges.

```ts
// vitest.config.ts (repo root)
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: ['apps/*/vitest.config.ts', 'packages/*/vitest.config.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
    },
  },
});
```

Each project sets `test.name` so reporter output identifies the workspace:

```ts
test: {
  name: '@acme/ui',
  environment: 'jsdom',
  // ...
}
```

## `tsconfig` for Tests

Add `vitest/globals` only when `globals: true`. With `globals: false`, import `describe`, `it`, `expect`, and `vi` from `vitest` explicitly. Add the jest-dom types once:

```json
{
  "compilerOptions": {
    "types": ["@testing-library/jest-dom/vitest", "vitest/importMeta"]
  }
}
```

## `playwright.config.ts`

```ts
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

const isCI = Boolean(process.env['CI']);
const baseURL = process.env['E2E_BASE_URL'] ?? 'http://localhost:5173';

export default defineConfig({
  testDir: './e2e',
  testMatch: '**/*.spec.ts',
  fullyParallel: true,
  forbidOnly: isCI,
  retries: isCI ? 2 : 0,
  workers: isCI ? 2 : undefined,
  reporter: isCI ? [['github'], ['html', { open: 'never' }]] : [['list']],
  timeout: 30_000,
  expect: { timeout: 5_000 },
  use: {
    baseURL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    locale: 'en-US',
    timezoneId: 'UTC',
  },
  projects: [
    { name: 'setup', testMatch: /auth\.setup\.ts/ },
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'], storageState: 'e2e/.auth/user.json' },
      dependencies: ['setup'],
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'], storageState: 'e2e/.auth/user.json' },
      dependencies: ['setup'],
    },
    {
      name: 'mobile-chrome',
      use: { ...devices['Pixel 7'], storageState: 'e2e/.auth/user.json' },
      dependencies: ['setup'],
    },
  ],
  webServer: {
    command: isCI ? 'pnpm preview --port 5173' : 'pnpm dev --port 5173',
    url: baseURL,
    reuseExistingServer: !isCI,
    timeout: 120_000,
  },
});
```

Authentication state is created once in `e2e/auth.setup.ts` and reused through `storageState`, so specs never repeat the sign-in flow.

```ts
// e2e/auth.setup.ts
import { expect, test as setup } from '@playwright/test';

import { LoginPage } from './pages/login.page';

setup('authenticate', async ({ page }) => {
  const login = new LoginPage(page);
  await login.goto();
  await login.signIn(process.env['E2E_USER'] ?? 'dash@example.com', process.env['E2E_PASSWORD'] ?? 'hunter22');
  await expect(page).toHaveURL(/\/dashboard$/);
  await page.context().storageState({ path: 'e2e/.auth/user.json' });
});
```

Add `e2e/.auth/` to `.gitignore`.

## `package.json` Scripts

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui",
    "test:e2e:report": "playwright show-report"
  }
}
```

## Common Commands

| Command                                                     | Purpose                                            |
| ----------------------------------------------------------- | -------------------------------------------------- |
| `pnpm vitest run`                                           | Run all tests once                                 |
| `pnpm vitest`                                               | Watch mode                                         |
| `pnpm vitest run src/features/auth`                         | Run tests under a directory                        |
| `pnpm vitest run -t "calls onSubmit"`                       | Filter tests by name substring                     |
| `pnpm vitest run --coverage`                                | Run with coverage and enforce thresholds           |
| `pnpm vitest run --project @acme/ui`                        | Run one monorepo project                           |
| `pnpm vitest run --reporter=verbose`                        | Print every test name                              |
| `pnpm vitest --ui`                                          | Browser UI with module graph and coverage          |
| `pnpm playwright test`                                      | Run all end-to-end specs                           |
| `pnpm playwright test e2e/login.spec.ts --project=chromium` | Run one spec on one browser                        |
| `pnpm playwright test --headed --debug`                     | Step through a spec with the inspector             |
| `pnpm playwright codegen http://localhost:5173`             | Record locators for a new page object              |
| `pnpm turbo run test --filter=...[origin/main]`             | Run tests only for workspaces changed since `main` |

## CI Workflow

```yaml
# .github/workflows/test.yml
name: test

on:
  pull_request:
  push:
    branches: [main]

jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm turbo run lint typecheck
      - run: pnpm turbo run test -- --coverage
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage
          path: '**/coverage/lcov.info'

  e2e:
    runs-on: ubuntu-latest
    needs: unit
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm exec playwright install --with-deps chromium
      - run: pnpm --filter web build
      - run: pnpm --filter web test:e2e --project=chromium
        env:
          CI: 'true'
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: apps/web/playwright-report
```

Run the full browser matrix (`webkit`, `mobile-chrome`) on `main` only; pull requests run `chromium`.
