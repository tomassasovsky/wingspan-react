---
name: react-architecture
description: Layered architecture for React apps in a pnpm workspace monorepo. Four layers (data, domain, business logic, presentation) with strict unidirectional dependencies, feature folders, the Page/View split, barrel exports, a composition root for providers and repositories, and ESLint-enforced boundaries. Use when structuring a React app or monorepo, creating api-client or repository packages, adding a feature, defining layer boundaries, wiring providers, or deciding where code belongs.
allowed-tools: Read Glob Grep
---

# Layered Architecture

Four layers with dependencies pointing one way only: Presentation -> Business Logic -> Domain -> Data. Data and Domain are workspace packages; Business Logic and Presentation live in feature folders inside the app.

---

## Core Standards

Apply these standards to ALL architecture work:

- **Four layers** — Data, Domain, Business Logic, Presentation; every feature spans exactly these layers
- **Unidirectional dependencies** — Presentation -> Business Logic -> Domain -> Data; never skip or invert a layer
- **Data and Domain live in `packages/`** — `<name>-api-client`, `<name>-storage`, `<name>-repository`, each with its own `package.json`
- **Business Logic and Presentation live in `apps/<app>/src/features/<feature>/`** — organized by feature, never by type
- **Data packages contain zero domain logic** — DTOs and `zod` schemas match the wire format exactly; the package is reusable in unrelated projects
- **Domain models live in repository packages** — the repository maps DTO -> model; API shapes never leak past the repository
- **No inter-repository imports** — repositories depend on data packages only; combine domains in a query hook
- **Presentation never imports a data package** — components and hooks reach data only through a repository
- **`packages/ui` imports nothing from data or domain** — it is a pure presentation dependency
- **Workspace protocol for local packages** — `"@acme/todos-repository": "workspace:*"`; never relative paths across packages
- **Barrel export at every package and feature boundary** — consumers import `@acme/todos-repository` or `@/features/todos`, never internal paths
- **Repositories receive clients as factory arguments** — never instantiate a client inside a repository
- **One composition root** — `src/app/` builds clients, repositories, the `QueryClient`, and the router; nothing else does
- **Boundaries are enforced by ESLint** — `eslint-plugin-boundaries` fails CI on any layer violation
- **Every layer ships with tests** — `msw` for clients, `vi.fn()` fakes for repositories, `renderHook` for hooks, Testing Library for views

## Architecture Overview

| Layer              | Responsibility                                    | Location                                                           | May import                    | Example                  |
| ------------------ | ------------------------------------------------- | ------------------------------------------------------------------ | ----------------------------- | ------------------------ |
| **Data**           | HTTP and storage clients, DTOs, `zod` schemas     | `packages/<name>-api-client/`, `packages/<name>-storage/`          | External packages only        | `@acme/todos-api-client` |
| **Domain**         | Repositories, domain models, DTO -> model mapping | `packages/<name>-repository/`                                      | Data                          | `@acme/todos-repository` |
| **Business logic** | Query hooks, mutations, `zustand` stores          | `apps/<app>/src/features/<f>/{api,hooks,store}/`                   | Domain                        | `useTodosQuery`          |
| **Presentation**   | Components, pages, routes                         | `apps/<app>/src/features/<f>/{components,routes}/`, `packages/ui/` | Business logic, `packages/ui` | `TodosPage`, `TodosView` |

```text
Presentation  (features/<f>/components, routes, @acme/ui)
      │ calls hooks, renders props
Business logic  (features/<f>/api, hooks, store)
      │ calls repository methods
Domain  (packages/<name>-repository)
      │ calls client methods
Data  (packages/<name>-api-client, <name>-storage)
```

## Monorepo Structure

```text
acme/
├── apps/web/
│   ├── src/
│   │   ├── app/                   # Composition root
│   │   │   ├── config.ts          # Parses VITE_* into a typed AppConfig
│   │   │   ├── repositories.tsx   # RepositoriesProvider + useRepositories
│   │   │   ├── bootstrap.ts       # createRepositories(config): the only data-package import
│   │   │   ├── providers.tsx      # QueryClientProvider > RepositoriesProvider
│   │   │   └── router.tsx         # createBrowserRouter with lazy feature routes
│   │   ├── features/todos/        # One folder per feature (below)
│   │   ├── lib/                   # App-wide helpers with no feature knowledge
│   │   ├── test/                  # setup.ts, render.tsx, fakes.ts
│   │   └── main.tsx
│   ├── eslint.config.js           # Boundaries enforced here
│   └── package.json
├── packages/
│   ├── todos-api-client/src/      # Data: index.ts, todos-api-client.ts, dto/, errors.ts
│   ├── todos-repository/src/      # Domain: index.ts, todos-repository.ts, models/, errors.ts
│   └── ui/                        # Presentation primitives (react-ui-package skill)
├── pnpm-workspace.yaml
├── turbo.json
└── tsconfig.base.json
```

## Feature Folder

```text
src/features/todos/
├── api/                         # Business logic
│   ├── todosQueries.ts          # Query key factory + queryOptions
│   ├── useTodosQuery.ts         # Query hook
│   └── useToggleTodoMutation.ts # Mutation hook with invalidation
├── components/                  # Presentation
│   ├── TodosView.tsx            # Renders from props only
│   └── TodosView.test.tsx
├── hooks/                       # Feature hooks that are not queries
├── store/                       # todosStore.ts (zustand), only for state shared across distant components
├── routes/
│   ├── TodosPage.tsx            # Wires hooks to the view
│   └── TodosPage.test.tsx
└── index.ts                     # Public barrel: only what other features and the router need
```

| Kind       | File name            | Export                          |
| ---------- | -------------------- | ------------------------------- |
| Component  | `TodosView.tsx`      | `export function TodosView`     |
| Page       | `TodosPage.tsx`      | `export function TodosPage`     |
| Hook       | `useTodosQuery.ts`   | `export function useTodosQuery` |
| Store      | `todosStore.ts`      | `export const useTodosStore`    |
| Query keys | `todosQueries.ts`    | `export const todosKeys`        |
| Test       | `TodosView.test.tsx` | colocated with the subject      |

## Layer Patterns

| Layer          | Pattern                                                                                                                                        |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Data           | `createTodosApiClient({ baseUrl, fetch })` returns typed methods; every response is parsed with a `zod` schema; non-2xx throws `TodosApiError` |
| Domain         | `createTodosRepository({ apiClient })` returns the `TodosRepository` type; `todoFromDto` maps wire -> model; API errors become domain errors   |
| Business logic | `todosKeys` factory + `queryOptions`; hooks call `useRepositories()`; mutations invalidate `todosKeys.lists()`                                 |
| Presentation   | `TodosPage` calls hooks and passes data down; `TodosView` renders props and is the unit of component testing                                   |

See [references/data-flow.md](references/data-flow.md) for the DTO schema, client, model, mapper, key factory, mutation, page, and view in full.

## Page/View Split

`XPage` wires hooks and mutations; `XView` renders from props with no data dependencies.

```tsx
// src/features/todos/routes/TodosPage.tsx
export function TodosPage() {
  const { data: todos } = useTodosQuery();
  const toggle = useToggleTodoMutation();

  return <TodosView todos={todos} isToggling={toggle.isPending} onToggle={(id) => toggle.mutate(id)} />;
}
```

`TodosView` takes `{ todos, isToggling, onToggle }` and renders a list of `Checkbox` components from `@acme/ui`; it imports only types from `@acme/todos-repository`. Full code in [references/data-flow.md](references/data-flow.md).

## Barrel Export Rules

| Boundary           | Barrel                      | Exports                                                 | Never exports                        |
| ------------------ | --------------------------- | ------------------------------------------------------- | ------------------------------------ |
| Data package       | `packages/*/src/index.ts`   | Client factory, client type, DTO types, errors          | Internal helpers such as `request`   |
| Repository package | `packages/*/src/index.ts`   | Repository factory, repository type, models, errors     | DTO types, mappers, client instances |
| Feature            | `src/features/<f>/index.ts` | Route component, hooks other features call, key factory | Views, internal components           |
| App                | none                        | Apps are not imported                                   |                                      |

Inside a package or feature, import files directly; the barrel is for consumers only. Barrels contain `export { x } from './x'` lines and nothing else.

## Composition Root

```tsx
// src/app/repositories.tsx
import { createContext, use, type ReactNode } from 'react';
import type { TodosRepository } from '@acme/todos-repository';

export type Repositories = { todos: TodosRepository };

const RepositoriesContext = createContext<Repositories | null>(null);

export function RepositoriesProvider({ value, children }: { value: Repositories; children: ReactNode }) {
  return <RepositoriesContext value={value}>{children}</RepositoriesContext>;
}

export function useRepositories(): Repositories {
  const repositories = use(RepositoriesContext);
  if (repositories === null) throw new Error('useRepositories must be used inside RepositoriesProvider');
  return repositories;
}
```

`bootstrap.ts` exports `createRepositories(config)` which builds each client and repository; `providers.tsx` nests `QueryClientProvider` > `RepositoriesProvider`; `main.tsx` calls `createRepositories(loadConfig())` once and renders `<Providers><RouterProvider router={router} /></Providers>`. Environments differ only in `AppConfig`; the wiring is identical.

## Enforcing Boundaries

`eslint-plugin-boundaries` turns the rules above into lint errors. Add this block to the `defineConfig([...])` array in `apps/web/eslint.config.js`:

```js
import boundaries from 'eslint-plugin-boundaries';

export const boundariesConfig = {
  files: ['src/**/*.{ts,tsx}'],
  plugins: { boundaries },
  settings: {
    'import/resolver': { typescript: { project: './tsconfig.json' } },
    'boundaries/include': ['src/**/*'],
    'boundaries/ignore': ['src/**/*.test.{ts,tsx}', 'src/**/*.d.ts'],
    'boundaries/elements': [
      { type: 'entry', pattern: 'src/main.tsx', mode: 'file' },
      { type: 'bootstrap', pattern: 'src/app/bootstrap.ts', mode: 'file' },
      { type: 'app', pattern: 'src/app/**/*', mode: 'full' },
      { type: 'feature-barrel', pattern: 'src/features/*/index.ts', mode: 'file', capture: ['feature'] },
      { type: 'feature', pattern: 'src/features/*/*', mode: 'folder', capture: ['feature', 'layer'] },
      { type: 'lib', pattern: 'src/lib/**/*', mode: 'full' },
      { type: 'test', pattern: 'src/test/**/*', mode: 'full' },
    ],
  },
  rules: {
    'boundaries/no-unknown-files': 'error',
    'boundaries/no-unknown': 'error',
    'boundaries/element-types': [
      'error',
      {
        default: 'disallow',
        rules: [
          { from: 'entry', allow: ['app'] },
          { from: ['bootstrap', 'app'], allow: ['app', 'bootstrap', 'lib', 'feature-barrel'] },
          { from: 'feature-barrel', allow: [['feature', { feature: '${from.feature}' }]] },
          // Presentation: own feature, other features' barrels, app, lib.
          {
            from: [['feature', { layer: 'components' }], ['feature', { layer: 'routes' }]],
            allow: [['feature', { feature: '${from.feature}' }], 'feature-barrel', 'app', 'lib'],
          },
          // Business logic: own feature's business logic only.
          {
            from: [['feature', { layer: 'api' }], ['feature', { layer: 'hooks' }], ['feature', { layer: 'store' }]],
            allow: [
              ['feature', { feature: '${from.feature}', layer: 'api' }],
              ['feature', { feature: '${from.feature}', layer: 'hooks' }],
              ['feature', { feature: '${from.feature}', layer: 'store' }],
              'app',
              'lib',
            ],
          },
          { from: 'lib', allow: ['lib'] },
          { from: 'test', allow: ['app', 'bootstrap', 'feature-barrel', 'feature', 'lib', 'test'] },
        ],
      },
    ],
    'boundaries/external': [
      'error',
      {
        default: 'allow',
        rules: [
          {
            from: ['app', 'feature', 'feature-barrel', 'lib', 'entry'],
            disallow: ['@acme/*-api-client', '@acme/*-storage'],
            message: 'Only src/app/bootstrap.ts may import a data package. Use the repository.',
          },
          {
            from: [['feature', { layer: 'components' }], ['feature', { layer: 'routes' }]],
            disallow: ['@acme/*-repository'],
            importKind: 'value',
            message: 'Presentation never calls a repository. Use a query hook from the feature api/ folder.',
          },
          {
            from: [['feature', { layer: 'api' }], ['feature', { layer: 'hooks' }], ['feature', { layer: 'store' }]],
            disallow: ['@acme/ui', 'react-router'],
            message: 'Business logic has no UI or routing dependencies.',
          },
        ],
      },
    ],
  },
};
```

Type-only imports of models from `@acme/*-repository` stay allowed in presentation (`importKind: 'value'`). In `packages/ui`, add `'no-restricted-imports'` with the pattern group `['@acme/*-api-client', '@acme/*-storage', '@acme/*-repository']`.

## Data Flow

Loading the todos list:

1. **Presentation** — the router lazy-loads `TodosPage` from `@/features/todos`, which calls `useTodosQuery()`
2. **Business logic** — `useSuspenseQuery(todosListOptions(todos))` suspends and runs `repository.getTodos()`
3. **Domain** — `getTodos` calls `apiClient.getTodos()` and maps each DTO with `todoFromDto`
4. **Data** — the client fetches `/todos`, throws `TodosApiError` on a non-2xx status, and parses the body with `todoDtoSchema.array()`
5. **Back up** — TanStack Query caches under `todosKeys.list()`; `TodosPage` renders `TodosView`; a mutation invalidates `todosKeys.lists()` and the cycle repeats

## Anti-Patterns

| Anti-Pattern                                   | Problem                                                      | Correct Approach                                                   |
| ---------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------ |
| Component calls `fetch` or an API client       | Skips domain mapping and caching; untestable without network | Component -> hook -> repository -> client                          |
| Repository imports another repository          | Tangled graph; cannot test in isolation                      | One repository per domain; compose in a query hook                 |
| DTO types used in components                   | Wire format changes break the UI                             | Map DTO -> model in the repository; presentation sees models only  |
| Business rules inside a repository             | Repository becomes a god object                              | Repository maps and orchestrates; rules live in hooks and stores   |
| Module-level singleton repository              | Hidden global; tests cannot substitute it                    | Build in `bootstrap.ts`; provide via `RepositoriesProvider`        |
| `zustand` store for server data                | Duplicate cache that goes stale                              | TanStack Query owns server state; `zustand` owns client-only state |
| Importing another feature's `components/` path | Couples features to internals                                | Import from `@/features/<feature>` (the barrel) only               |
| Relative path or `file:` dependency            | Bypasses the build and breaks when files move                | `"@acme/pkg": "workspace:*"`                                       |
| Page renders markup and fetches data           | Cannot test rendering without providers                      | `XPage` wires data; `XView` renders props                          |
| Boundaries documented but not linted           | Violations land silently                                     | `eslint-plugin-boundaries` config above, run in CI                 |

## Common Workflows

### Adding a data package

1. Scaffold `packages/<name>-api-client` with the **react-create-project** skill (`react_package`, no `react`)
2. Write DTO schemas in `src/dto/` with `zod`; export inferred types
3. Write `create<Name>ApiClient` with injected `fetch`, typed errors, and schema parsing on every response
4. Export from `src/index.ts`; add `msw` tests per [references/testing.md](references/testing.md)

### Adding a repository

1. Scaffold `packages/<name>-repository`; add `"@acme/<name>-api-client": "workspace:*"`
2. Write models in `src/models/` with mapper functions `xFromDto`
3. Write `create<Name>Repository({ apiClient })` returning the `<Name>Repository` type; translate API errors to domain errors
4. Export from `src/index.ts`; test with `vi.fn()` fakes of the client

### Connecting a repository to a feature

1. Add `"@acme/<name>-repository": "workspace:*"` to the app
2. Add the field to `Repositories` and construct it in `bootstrap.ts`
3. Create `features/<feature>/api/` with the key factory, query hook, and mutation hooks
4. Create `XPage` in `routes/` and `XView` in `components/`; register the route in `src/app/router.tsx`
5. Export the page from `features/<feature>/index.ts`; run `pnpm lint` to confirm the boundaries pass

## Additional Resources

- [references/data-flow.md](references/data-flow.md) — complete code for the `todos` request path: DTO schema, client, model and mapper, repository, composition root, key factory, hooks, page, and view
- [references/package-manifests.md](references/package-manifests.md) — `package.json` for an api-client, a repository, and the app; `pnpm-workspace.yaml`; `turbo.json`; `tsconfig.base.json`; workspace protocol
- [references/testing.md](references/testing.md) — how each layer is tested: `msw` for clients, `vi.fn()` for repositories, `renderHook` for hooks, Testing Library for views and pages
- [references/worked-example.md](references/worked-example.md) — adding an `orders` feature end to end with every file and test
- For scaffolding packages and apps see the **react-create-project** skill; for `packages/ui` see the **react-ui-package** skill
