# Post-Scaffold Setup

Complete configuration files applied to every new project. Copy each file verbatim, then adjust only the noted per-template differences.

---

## `.nvmrc`

```text
24
```

## `package.json` additions

```json
{
  "type": "module",
  "engines": { "node": ">=24", "pnpm": ">=10" },
  "packageManager": "pnpm@10.15.0",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "lint": "eslint .",
    "format": "prettier --write .",
    "format:check": "prettier --check .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage"
  }
}
```

Set `packageManager` to the output of `pnpm --version` so the pin matches the machine that scaffolded the project.

## `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "moduleDetection": "force",
    "jsx": "react-jsx",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "skipLibCheck": true,
    "noEmit": true,
    "types": ["vite/client"],
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] }
  },
  "include": ["src", "vite.config.ts", "vitest.config.ts", "eslint.config.js"]
}
```

For a Vite app, place these `compilerOptions` in `tsconfig.app.json` and keep the root `tsconfig.json` with its project `references`. For a library package remove `"types": ["vite/client"]` and the `@/*` alias; data-layer packages also drop `"DOM"` and `"DOM.Iterable"` from `lib`.

## `eslint.config.js`

```js
import js from '@eslint/js';
import { defineConfig, globalIgnores } from 'eslint/config';
import prettier from 'eslint-config-prettier/flat';
import { createTypeScriptImportResolver } from 'eslint-import-resolver-typescript';
import importX from 'eslint-plugin-import-x';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import reactHooks from 'eslint-plugin-react-hooks';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default defineConfig([
  globalIgnores(['dist', 'coverage', 'storybook-static', '.next', 'node_modules']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      js.configs.recommended,
      tseslint.configs.strictTypeChecked,
      tseslint.configs.stylisticTypeChecked,
      reactHooks.configs.flat.recommended,
      jsxA11y.flatConfigs.recommended,
      importX.flatConfigs.recommended,
      importX.flatConfigs.typescript,
    ],
    languageOptions: {
      ecmaVersion: 2024,
      globals: { ...globals.browser },
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    settings: {
      'import-x/resolver-next': [createTypeScriptImportResolver()],
    },
    rules: {
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { prefer: 'type-imports', fixStyle: 'inline-type-imports' },
      ],
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', ignoreRestSiblings: true },
      ],
      '@typescript-eslint/restrict-template-expressions': ['error', { allowNumber: true }],
      'import-x/no-default-export': 'error',
      'import-x/no-cycle': 'error',
      'import-x/no-unresolved': 'error',
      'import-x/order': [
        'error',
        {
          groups: ['builtin', 'external', 'internal', ['parent', 'sibling', 'index'], 'type'],
          'newlines-between': 'always',
          alphabetize: { order: 'asc', caseInsensitive: true },
        },
      ],
    },
  },
  {
    // Files that frameworks require to default-export.
    files: [
      '**/*.config.{ts,js,mjs}',
      '**/*.stories.tsx',
      'src/app/**/{page,layout,loading,error,not-found,template,default}.tsx',
      'src/app/**/route.ts',
    ],
    rules: { 'import-x/no-default-export': 'off' },
  },
  {
    files: ['**/*.test.{ts,tsx}', 'src/test/**/*.{ts,tsx}'],
    languageOptions: { globals: { ...globals.node } },
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@typescript-eslint/unbound-method': 'off',
    },
  },
  prettier,
]);
```

Data-layer and repository packages replace `globals.browser` with `globals.node` and drop `reactHooks` and `jsxA11y` from `extends`.

## `.prettierrc`

```json
{
  "singleQuote": true,
  "semi": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2,
  "arrowParens": "always",
  "endOfLine": "lf"
}
```

When Tailwind is present add `"plugins": ["prettier-plugin-tailwindcss"]` and install it.

`.prettierignore`:

```text
dist
coverage
storybook-static
.next
pnpm-lock.yaml
```

## `vitest.config.ts`

```ts
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    environment: 'jsdom',
    globals: false,
    css: false,
    restoreMocks: true,
    setupFiles: ['./src/test/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      include: ['src/**/*.{ts,tsx}'],
      exclude: [
        'src/**/*.test.{ts,tsx}',
        'src/**/*.stories.tsx',
        'src/**/*.d.ts',
        'src/**/index.ts',
        'src/main.tsx',
        'src/test/**',
      ],
      thresholds: { lines: 100, functions: 100, branches: 100, statements: 100 },
    },
  },
});
```

`globals: false` keeps `describe`, `it`, and `expect` as explicit imports from `vitest`. Data-layer and repository packages use `environment: 'node'` and drop the `react()` plugin.

## `src/test/setup.ts`

```ts
import '@testing-library/jest-dom/vitest';

import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(() => {
  cleanup();
});
```

`cleanup` is required because auto-cleanup only runs when `globals: true`.

## `src/test/render.tsx`

```tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, type RenderOptions, type RenderResult } from '@testing-library/react';
import type { ReactElement, ReactNode } from 'react';

type RenderWithProvidersOptions = Omit<RenderOptions, 'wrapper'> & {
  queryClient?: QueryClient;
};

export function createTestQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: Number.POSITIVE_INFINITY },
      mutations: { retry: false },
    },
  });
}

export function renderWithProviders(
  ui: ReactElement,
  { queryClient = createTestQueryClient(), ...options }: RenderWithProvidersOptions = {},
): RenderResult & { queryClient: QueryClient } {
  function Wrapper({ children }: { children: ReactNode }) {
    return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
  }

  return { ...render(ui, { wrapper: Wrapper, ...options }), queryClient };
}
```

Extend `Wrapper` with the router and repository providers as the app grows. See the **react-architecture** skill for the provider list.

## Smoke test: `src/App.test.tsx`

```tsx
import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { App } from './App';
import { renderWithProviders } from './test/render';

describe('App', () => {
  it('renders the heading', () => {
    renderWithProviders(<App />);

    expect(screen.getByRole('heading', { level: 1 })).toBeInTheDocument();
  });
});
```

Convert the scaffold's `export default App` to a named `export function App()` so the barrel rule holds.

## Next.js differences

| Concern    | Next.js setting                                                                                                 |
| ---------- | --------------------------------------------------------------------------------------------------------------- |
| ESLint     | Keep `eslint.config.mjs`; put `...nextVitals` from `eslint-config-next` before our blocks; keep `prettier` last |
| tsconfig   | Keep `"plugins": [{ "name": "next" }]`, `"jsx": "preserve"`, and `.next/types/**/*.ts` in `include`             |
| Vitest     | Same config; add `environmentMatchGlobs: [['src/app/**/route.ts', 'node']]` for route handlers                  |
| Scripts    | `dev: next dev`, `build: next build`, `start: next start`, `typecheck: tsc --noEmit`                            |
| Components | Files that must default-export are covered by the `src/app/**` override in `eslint.config.js`                   |

## Library package differences

| Concern  | Library setting                                                                        |
| -------- | -------------------------------------------------------------------------------------- |
| Build    | `tsup.config.ts`; `build: tsup`, `dev: tsup --watch`                                   |
| tsconfig | No `@/*` alias; `"include": ["src"]`; no `vite/client` types                           |
| Coverage | `thresholds` stay at 100; exclude only `src/index.ts` and test files                   |
| Exports  | `exports` map with `types` before `import`; `sideEffects: false` unless CSS is shipped |
