# Package Manifests

Workspace and package manifests that encode the layer rules. Replace `@acme` with the workspace scope.

---

## Root

### `pnpm-workspace.yaml`

```yaml
packages:
  - 'apps/*'
  - 'packages/*'
```

### `package.json`

```json
{
  "name": "acme",
  "private": true,
  "type": "module",
  "engines": { "node": ">=24", "pnpm": ">=10" },
  "packageManager": "pnpm@10.15.0",
  "scripts": {
    "dev": "turbo run dev",
    "build": "turbo run build",
    "lint": "turbo run lint",
    "typecheck": "turbo run typecheck",
    "test": "turbo run test",
    "test:coverage": "turbo run test:coverage",
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  },
  "devDependencies": {
    "prettier": "^3.6.0",
    "turbo": "^2.5.0",
    "typescript": "^5.9.0"
  }
}
```

### `turbo.json`

```json
{
  "$schema": "https://turbo.build/schema.json",
  "globalEnv": ["NODE_ENV"],
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**", "!.next/cache/**", "storybook-static/**"]
    },
    "dev": { "cache": false, "persistent": true },
    "lint": { "dependsOn": ["^build"] },
    "typecheck": { "dependsOn": ["^build"] },
    "test": { "dependsOn": ["^build"] },
    "test:coverage": { "dependsOn": ["^build"], "outputs": ["coverage/**"] }
  }
}
```

`^build` means "build my workspace dependencies first", so an app never lints or tests against a stale `dist`.

### `tsconfig.base.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "moduleDetection": "force",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "resolveJsonModule": true,
    "skipLibCheck": true
  }
}
```

Apps and `packages/ui` add `"lib": ["ES2023", "DOM", "DOM.Iterable"]` and `"jsx": "react-jsx"`. Data and domain packages keep the base `lib` so a DOM import is a type error.

---

## Data package: `packages/todos-api-client/package.json`

```json
{
  "name": "@acme/todos-api-client",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "sideEffects": false,
  "files": ["dist"],
  "exports": {
    ".": { "types": "./dist/index.d.ts", "import": "./dist/index.js" },
    "./package.json": "./package.json"
  },
  "scripts": {
    "build": "tsup",
    "dev": "tsup --watch",
    "lint": "eslint .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:coverage": "vitest run --coverage"
  },
  "dependencies": {
    "zod": "^4.0.0"
  },
  "devDependencies": {
    "msw": "^2.10.0",
    "tsup": "^8.5.0",
    "typescript": "^5.9.0",
    "vitest": "^3.2.0",
    "@vitest/coverage-v8": "^3.2.0"
  }
}
```

No `react`, no `@acme/*` dependency. External packages only.

### `packages/todos-api-client/tsup.config.ts`

```ts
import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['esm'],
  dts: true,
  sourcemap: true,
  clean: true,
  target: 'es2022',
});
```

### `packages/todos-api-client/tsconfig.json`

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": { "noEmit": true, "types": ["node"] },
  "include": ["src", "tsup.config.ts", "vitest.config.ts"]
}
```

---

## Repository package: `packages/todos-repository/package.json`

```json
{
  "name": "@acme/todos-repository",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "sideEffects": false,
  "files": ["dist"],
  "exports": {
    ".": { "types": "./dist/index.d.ts", "import": "./dist/index.js" },
    "./package.json": "./package.json"
  },
  "scripts": {
    "build": "tsup",
    "dev": "tsup --watch",
    "lint": "eslint .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:coverage": "vitest run --coverage"
  },
  "dependencies": {
    "@acme/todos-api-client": "workspace:*"
  },
  "devDependencies": {
    "tsup": "^8.5.0",
    "typescript": "^5.9.0",
    "vitest": "^3.2.0",
    "@vitest/coverage-v8": "^3.2.0"
  }
}
```

Exactly one workspace dependency: its own data package. Never another `*-repository`.

Add `external: ['@acme/todos-api-client']` to `tsup.config.ts` so the client is not bundled into the repository's `dist`; `tsup` externalizes `dependencies` by default, so this is only needed when the client is listed elsewhere.

---

## App: `apps/web/package.json`

```json
{
  "name": "@acme/web",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "lint": "eslint .",
    "typecheck": "tsc --noEmit -p tsconfig.app.json",
    "test": "vitest run",
    "test:coverage": "vitest run --coverage"
  },
  "dependencies": {
    "@acme/todos-api-client": "workspace:*",
    "@acme/todos-repository": "workspace:*",
    "@acme/ui": "workspace:*",
    "@tanstack/react-query": "^5.80.0",
    "react": "^19.1.0",
    "react-dom": "^19.1.0",
    "react-router": "^7.6.0",
    "zod": "^4.0.0",
    "zustand": "^5.0.0"
  },
  "devDependencies": {
    "@testing-library/jest-dom": "^6.6.0",
    "@testing-library/react": "^16.3.0",
    "@testing-library/user-event": "^14.6.0",
    "@types/react": "^19.1.0",
    "@types/react-dom": "^19.1.0",
    "@vitejs/plugin-react": "^4.5.0",
    "eslint-plugin-boundaries": "^5.0.0",
    "jsdom": "^26.1.0",
    "msw": "^2.10.0",
    "typescript": "^5.9.0",
    "vite": "^7.0.0",
    "vitest": "^3.2.0"
  }
}
```

The app lists the data package only because `src/app/bootstrap.ts` constructs the client. ESLint (`boundaries/external`) blocks every other file from importing it.

---

## Workspace protocol

| Form            | Meaning                                              | Use                     |
| --------------- | ---------------------------------------------------- | ----------------------- |
| `"workspace:*"` | Link the local package at whatever version it has    | Always inside the repo  |
| `"workspace:^"` | Link locally; publish as `^<version>`                | Only for published libs |
| `"file:../pkg"` | Copies instead of links; ignores the package's build | Never                   |
| `"link:../pkg"` | Symlink without workspace semantics                  | Never                   |

`pnpm install` at the root links every `workspace:*` dependency into `node_modules`; `pnpm --filter @acme/web add @acme/orders-repository@workspace:*` adds a new one.
