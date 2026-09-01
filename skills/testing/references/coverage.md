# Coverage

## Measuring

```bash
pnpm vitest run --coverage                     # text summary + lcov + html in ./coverage
pnpm vitest run --coverage --coverage.reporter=text-summary
pnpm vitest run --coverage src/features/auth   # scoped run still reports against include globs
open coverage/index.html                       # browse uncovered lines and branches
```

Coverage uses the `v8` provider. Thresholds are read from `vitest.config.ts` and a run that falls below any threshold exits non-zero, which fails CI.

## Thresholds

| Workspace             | Lines | Functions | Branches | Statements | Rationale                                                                          |
| --------------------- | ----- | --------- | -------- | ---------- | ---------------------------------------------------------------------------------- |
| `packages/*`          | 100   | 100       | 100      | 100        | Shared code; every branch is a public contract                                     |
| `apps/*` features     | 100   | 100       | 100      | 100        | Feature logic and components                                                       |
| `apps/*` route wiring | n/a   | n/a       | n/a      | n/a        | Excluded via `coverage.exclude`: `main.tsx`, router assembly, provider composition |

```ts
coverage: {
  provider: 'v8',
  thresholds: {
    lines: 100,
    functions: 100,
    branches: 100,
    statements: 100,
  },
}
```

`thresholds.autoUpdate: true` is never enabled; thresholds move only through code review.

Per-glob thresholds allow a lower bar for a directory during migration; remove the entry when the migration ends:

```ts
thresholds: {
  lines: 100,
  functions: 100,
  branches: 100,
  statements: 100,
  'src/legacy/**': { lines: 80, functions: 80, branches: 70, statements: 80 },
},
```

## Ignoring Files

Exclude files that contain no logic or are generated. Never exclude a file because it is hard to test.

```ts
coverage: {
  include: ['src/**/*.{ts,tsx}'],
  exclude: [
    'src/**/*.test.{ts,tsx}',
    'src/**/*.stories.tsx',
    'src/**/*.d.ts',
    'src/**/index.ts',            // barrels
    'src/test/**',                // helpers, handlers, factories
    'src/main.tsx',               // bootstrap
    'src/app/router.tsx',         // route table assembly
    'src/**/generated/**',        // codegen output (openapi, graphql)
    'src/**/*.gen.ts',
  ],
},
```

| Marker                             | Scope                    | Use when                                                      |
| ---------------------------------- | ------------------------ | ------------------------------------------------------------- |
| `/* v8 ignore next */`             | Next statement           | Defensive `throw` after an exhaustive `switch`                |
| `/* v8 ignore start */` ... `stop` | Block                    | Environment-only branches (`import.meta.env.DEV` dev tooling) |
| `/* v8 ignore file */`             | Whole file (Vitest 3.2+) | Generated modules that cannot be excluded by glob             |

Every ignore marker includes a trailing comment explaining why:

```ts
default: {
  /* v8 ignore next -- exhaustive switch; unreachable at runtime */
  throw new Error(`Unhandled status: ${String(status satisfies never)}`);
}
```

## Gaps That Matter

100% lines with untested behavior is common. Review the branch column and the following cases before trusting a green report.

| Gap                                             | How to find it                             | Test to add                                              |
| ----------------------------------------------- | ------------------------------------------ | -------------------------------------------------------- |
| Conditional rendering (`a ? <X/> : <Y/>`, `&&`) | Branch coverage below 100 on the JSX line  | One test per branch: loading, empty, error, success      |
| Optional chaining and `??` defaults             | Branch coverage on the expression          | Test with the value present and absent                   |
| Error paths in clients and repositories         | `catch` blocks uncovered                   | `msw` handler returning 4xx, 5xx, `HttpResponse.error()` |
| `zod` schema refinements                        | `refine`/`superRefine` callbacks uncovered | Parse valid and invalid inputs                           |
| Mapper functions (DTO to model)                 | Optional fields never `undefined`          | Fixtures with each optional field omitted                |
| Event handlers                                  | Function coverage on `onClick`, `onChange` | Interaction tests through `user`                         |
| Callback props (`onSuccess`, `onError`)         | Function coverage on `useMutation` options | Trigger the mutation and assert the callback             |
| Query `enabled` and `select` options            | Branch coverage in query hooks             | `renderHook` with the enabling condition true and false  |
| `zustand` store actions                         | Function coverage on store slices          | Call the action and assert `store.getState()`            |
| Early returns and guard clauses                 | Line coverage on the `return`              | Test the guard input                                     |

## What Not to Chase

| Item                                 | Why                                                  |
| ------------------------------------ | ---------------------------------------------------- |
| Barrel `index.ts` files              | Re-exports contain no logic                          |
| Type-only files                      | Erased at compile time                               |
| Storybook stories                    | Covered by Storybook interaction tests, not `vitest` |
| Provider composition in `main.tsx`   | Covered by Playwright smoke tests                    |
| Third-party wrappers with zero logic | Move logic out; leave the wrapper excluded           |

## Coverage-Driven Patterns

Testing every branch of a status-driven component:

```tsx
describe('OrderStatusBadge', () => {
  it.each([
    ['open', /open/i],
    ['shipped', /shipped/i],
    ['cancelled', /cancelled/i],
  ] as const)('renders %s label when status is %s', (status, label) => {
    renderWithProviders(<OrderStatusBadge status={status} />);

    expect(screen.getByRole('status')).toHaveTextContent(label);
  });
});
```

Testing a mapper with optional fields:

```ts
describe('toUser', () => {
  it('maps every field when all are present', () => {
    expect(toUser({ id: '1', name: 'Dash', email: 'dash@example.com', avatar_url: 'https://x/y.png' }))
      .toStrictEqual({ id: '1', name: 'Dash', email: 'dash@example.com', avatarUrl: 'https://x/y.png' });
  });

  it('sets avatarUrl to null when avatar_url is missing', () => {
    expect(toUser({ id: '1', name: 'Dash', email: 'dash@example.com' }).avatarUrl).toBeNull();
  });
});
```

## Monorepo Pipeline

```json
// turbo.json
{
  "tasks": {
    "test": {
      "dependsOn": ["^build"],
      "outputs": ["coverage/**"],
      "inputs": ["src/**", "vitest.config.ts", "package.json"]
    }
  }
}
```

Each workspace enforces its own thresholds; the root `projects` run merges reports for the CI artifact. Upload `**/coverage/lcov.info` so reviewers can inspect uncovered lines from the pull request.
