# Build Configuration

Every config file for `packages/ui`. Replace `@acme` with the workspace scope.

---

## `package.json`

```json
{
  "name": "@acme/ui",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "sideEffects": ["**/*.css"],
  "files": ["dist", "src/styles"],
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js"
    },
    "./theme.css": "./src/styles/theme.css",
    "./package.json": "./package.json"
  },
  "scripts": {
    "build": "tsup",
    "dev": "tsup --watch",
    "lint": "eslint .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "storybook": "storybook dev -p 6006",
    "build-storybook": "storybook build",
    "test-storybook": "test-storybook"
  },
  "peerDependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "dependencies": {
    "@radix-ui/react-checkbox": "^1.3.0",
    "@radix-ui/react-dialog": "^1.1.0",
    "@radix-ui/react-slot": "^1.2.0",
    "class-variance-authority": "^0.7.1",
    "clsx": "^2.1.0",
    "tailwind-merge": "^3.3.0"
  },
  "devDependencies": {
    "@storybook/addon-a11y": "^8.6.0",
    "@storybook/addon-essentials": "^8.6.0",
    "@storybook/addon-interactions": "^8.6.0",
    "@storybook/react": "^8.6.0",
    "@storybook/react-vite": "^8.6.0",
    "@storybook/test": "^8.6.0",
    "@storybook/test-runner": "^0.22.0",
    "@tailwindcss/vite": "^4.1.0",
    "@testing-library/jest-dom": "^6.6.0",
    "@testing-library/react": "^16.3.0",
    "@testing-library/user-event": "^14.6.0",
    "@types/react": "^19.1.0",
    "@types/react-dom": "^19.1.0",
    "@vitejs/plugin-react": "^4.5.0",
    "@vitest/coverage-v8": "^3.2.0",
    "jsdom": "^26.1.0",
    "react": "^19.1.0",
    "react-dom": "^19.1.0",
    "storybook": "^8.6.0",
    "tailwindcss": "^4.1.0",
    "tsup": "^8.5.0",
    "typescript": "^5.9.0",
    "vitest": "^3.2.0",
    "vitest-axe": "^1.0.0"
  }
}
```

| Field              | Why                                                                                            |
| ------------------ | ---------------------------------------------------------------------------------------------- |
| `sideEffects`      | Only CSS has side effects; bundlers drop unused components from `dist/index.js`                |
| `exports`          | Two public entry points; `types` first so TypeScript resolves declarations before the JS file  |
| `files`            | `src/styles` ships so `./theme.css` resolves after publish; `dist` carries the compiled code   |
| `peerDependencies` | `react` and `react-dom` are provided by the app; a second React copy breaks hooks              |
| `dependencies`     | Runtime libraries the components import; Radix packages are listed one by one as they are used |
| `devDependencies`  | `react` and `react-dom` appear here too so tests and Storybook run inside the package          |

---

## `tsup.config.ts`

```ts
import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['esm'],
  dts: true,
  sourcemap: true,
  clean: true,
  splitting: true,
  treeshake: true,
  target: 'es2022',
  external: ['react', 'react-dom', 'react/jsx-runtime'],
  banner: { js: "'use client';" },
  esbuildOptions(options) {
    options.jsx = 'automatic';
  },
});
```

| Option      | Why                                                                                 |
| ----------- | ----------------------------------------------------------------------------------- |
| `format`    | ESM only; every consumer in the workspace is ESM                                    |
| `dts`       | Emits `dist/index.d.ts` from the barrel so `ButtonProps` and friends are importable |
| `splitting` | Shared chunks between components instead of duplicated code                         |
| `external`  | Never bundle React; `jsx-runtime` must resolve to the app's React                   |
| `banner`    | Marks the bundle as client components for Next.js App Router consumers              |
| `jsx`       | The automatic runtime; no `import React` in components                              |

---

## `tsconfig.json`

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "jsx": "react-jsx",
    "noEmit": true
  },
  "include": ["src", ".storybook", "tsup.config.ts", "vitest.config.ts"]
}
```

`globals: false` in Vitest means no `vitest/globals` types are needed; every test imports `describe`, `it`, and `expect` from `vitest`.

---

## `vitest.config.ts`

```ts
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react()],
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
      exclude: ['src/**/*.test.{ts,tsx}', 'src/**/*.stories.tsx', 'src/**/index.ts', 'src/test/**'],
      thresholds: { lines: 100, functions: 100, branches: 100, statements: 100 },
    },
  },
});
```

## `src/test/setup.ts`

```ts
import '@testing-library/jest-dom/vitest';
import 'vitest-axe/extend-expect';

import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(() => {
  cleanup();
});
```

---

## `.storybook/main.ts`

```ts
import type { StorybookConfig } from '@storybook/react-vite';

const config: StorybookConfig = {
  framework: { name: '@storybook/react-vite', options: {} },
  stories: ['../src/**/*.stories.tsx'],
  addons: ['@storybook/addon-essentials', '@storybook/addon-a11y', '@storybook/addon-interactions'],
  async viteFinal(viteConfig) {
    const { default: tailwindcss } = await import('@tailwindcss/vite');
    return { ...viteConfig, plugins: [...(viteConfig.plugins ?? []), tailwindcss()] };
  },
};

export default config;
```

## `.storybook/preview.tsx`

```tsx
import type { Preview } from '@storybook/react';

import '../src/styles/storybook.css';

const preview: Preview = {
  parameters: {
    a11y: { test: 'error' },
    controls: { matchers: { color: /(background|color)$/i } },
  },
  globalTypes: {
    theme: {
      description: 'Color theme',
      toolbar: { icon: 'mirror', items: ['light', 'dark'], dynamicTitle: true },
    },
  },
  initialGlobals: { theme: 'light' },
  decorators: [
    (Story, { globals }) => {
      document.documentElement.dataset.theme = globals.theme === 'dark' ? 'dark' : 'light';
      return <Story />;
    },
  ],
};

export default preview;
```

## `src/styles/storybook.css`

```css
@import 'tailwindcss';
@import './theme.css';
@source '../';
```

This file exists only for the catalog; the package never ships compiled CSS. Apps import `@acme/ui/theme.css` into their own Tailwind entry.

---

## ESLint additions for `packages/ui`

Add to the `defineConfig([...])` array from the **react-create-project** skill:

```js
{
  files: ['src/**/*.{ts,tsx}'],
  rules: {
    'no-restricted-imports': [
      'error',
      {
        patterns: [
          {
            group: ['@acme/*-api-client', '@acme/*-storage', '@acme/*-repository', '@tanstack/react-query', 'react-router'],
            message: 'packages/ui is presentation only. Pass data and callbacks as props.',
          },
        ],
      },
    ],
  },
},
{
  files: ['src/**/*.stories.tsx', '.storybook/**/*.{ts,tsx}'],
  rules: { 'import-x/no-default-export': 'off' },
},
```

---

## Consuming the package from an app

```bash
pnpm --filter @acme/web add @acme/ui@workspace:*
```

```css
/* apps/web/src/index.css */
@import 'tailwindcss';
@import '@acme/ui/theme.css';
@source '../../../packages/ui/src';
```

```tsx
import { Button } from '@acme/ui';

export function SaveBar({ onSave, isSaving }: { onSave: () => void; isSaving: boolean }) {
  return (
    <Button onClick={onSave} isLoading={isSaving}>
      Save
    </Button>
  );
}
```

`turbo.json` has `"build": { "dependsOn": ["^build"] }`, so `pnpm build` at the root compiles `packages/ui` before `apps/web`. During development run `pnpm --filter @acme/ui dev` alongside the app so `dist/` rebuilds on change.
