---
name: react-create-project
description: Scaffold a new React project with pnpm and apply the standard post-scaffold setup (strict TypeScript, ESLint 9 flat config, Prettier, Vitest with Testing Library). Supports Vite SPA, Next.js App Router, library package, UI component package, and pnpm workspace monorepo templates. Use when user says "create a new project", "start a new react app", "new next app", "scaffold a package", "create a component library", or "set up a monorepo".
allowed-tools: Bash Read Write Glob AskUserQuestion
argument-hint: "[project-name] [what you are building]"
---

# Create Project

Scaffold a new React project with `pnpm`, then apply the tooling every project gets on day one.

---

## Core Standards

Apply these standards to ALL project scaffolding:

- **Use `pnpm` for everything** — `pnpm create`, `pnpm add`, `pnpm dlx`; never `npm`, `npx`, or `yarn`
- **Infer the template from context** — decide from what the user is building; never ask them to pick a template name
- **Use `AskUserQuestion` only for what you cannot infer** — the project name is the usual gap; never ask about optional flags
- **Project names are kebab-case** — valid npm names use lowercase letters, digits, and hyphens; convert `MyApp` and `my_app` to `my-app`
- **Apply the post-scaffold setup to every template** — strict `tsconfig`, ESLint flat config, Prettier, Vitest + Testing Library, `.nvmrc`, `engines`, standard scripts
- **Pin the toolchain** — `.nvmrc` and `engines.node` on the current LTS; `packageManager` on the installed `pnpm` version
- **Verify before reporting done** — run `pnpm lint`, `pnpm typecheck`, and `pnpm test`; fix failures before handing off
- **Commit nothing** — leave the working tree for the user to review

## Template Selection

| Template        | Use when the user wants                                       | Produces                                                 |
| --------------- | ------------------------------------------------------------- | -------------------------------------------------------- |
| `vite_app`      | A SPA, dashboard, internal tool, or client-only app           | Vite + React 19 + TypeScript + React Router v7           |
| `next_app`      | SSR, SEO, full-stack, API routes, or server components        | Next.js App Router with `src/` and ESLint                |
| `react_package` | A shared hooks, utilities, or domain library consumed by apps | `tsup` library build, `exports` map, Vitest              |
| `ui_package`    | A component library or design system                          | `react_package` plus Storybook 8 and `addon-a11y`        |
| `monorepo`      | Several apps or packages in one repo, or layered architecture | pnpm workspaces + Turborepo with `apps/` and `packages/` |

Decision rules:

- "Website", "marketing", "SEO", "server", "API route", "full-stack" => `next_app`
- "App", "dashboard", "tool", "admin" with no server needs => `vite_app`
- "Components", "design system", "Storybook" => `ui_package`
- "Package", "library", "shared hooks", "SDK", "api client", "repository" => `react_package`
- "Apps and packages", "monorepo", "workspace", or any request for the layered architecture => `monorepo`, then scaffold apps and packages inside it
- "Build something with React" with no other signal => ask one high-level question about what they are building

## Workflow

### Step 1: Infer the template and gather parameters

1. Pick the template from the decision rules above
2. Derive the project name from the request; convert to kebab-case
3. Use `AskUserQuestion` once, batching only the missing required values (name, and for `monorepo` the npm scope such as `@acme`)
4. Check the target directory with `Glob` so an existing folder is never overwritten

### Step 2: Scaffold

Run the template commands below from the parent directory (or from `apps/` or `packages/` inside a monorepo).

### Step 3: Apply the post-scaffold setup

Write every file listed in [references/post-scaffold.md](references/post-scaffold.md), install the dev dependencies, and set the standard scripts. Overwrite the scaffold's own `eslint.config.js`, `tsconfig.json`, and `.prettierrc` with ours.

### Step 4: Verify

```bash
pnpm install
pnpm lint && pnpm typecheck && pnpm test
```

Report the created path, the template used, and the next command to run (`pnpm dev`, `pnpm storybook`, or `pnpm build`).

## Templates

### `vite_app`

```bash
pnpm create vite my-app --template react-ts
cd my-app
pnpm install
pnpm add react-router @tanstack/react-query zod
```

Answer "No" to any extra prompt from `create vite`. Vite splits its `tsconfig` into `tsconfig.app.json` and `tsconfig.node.json`; apply our `compilerOptions` to `tsconfig.app.json` and keep the project references.

### `next_app`

```bash
pnpm create next-app@latest my-site --ts --app --eslint --src-dir --use-pnpm --no-tailwind --import-alias "@/*"
cd my-site
pnpm add @tanstack/react-query zod
```

Use `--tailwind` instead of `--no-tailwind` when the user asks for Tailwind. Keep the generated `eslint.config.mjs` and add our blocks on top of `eslint-config-next`; keep `next dev`, `next build`, and `next start` scripts. See the Next.js section of [references/post-scaffold.md](references/post-scaffold.md).

### `react_package`

There is no CLI scaffold. Create the layout by hand:

```bash
mkdir -p my-lib/src && cd my-lib
pnpm init
pnpm add -D typescript tsup react react-dom @types/react @types/react-dom
```

Then set the manifest fields that make it a library:

```json
{
  "name": "@acme/my-lib",
  "version": "0.1.0",
  "type": "module",
  "sideEffects": false,
  "files": ["dist"],
  "exports": {
    ".": { "types": "./dist/index.d.ts", "import": "./dist/index.js" },
    "./package.json": "./package.json"
  },
  "peerDependencies": { "react": "^19.0.0", "react-dom": "^19.0.0" }
}
```

Add `src/index.ts` as the barrel and a `tsup.config.ts` with `entry: ['src/index.ts'], format: ['esm'], dts: true, clean: true`. Data-layer and repository packages drop `react` and `react-dom` entirely and use `environment: 'node'` in Vitest.

### `ui_package`

Run the `react_package` steps, then:

```bash
pnpm add @radix-ui/react-slot class-variance-authority clsx tailwind-merge
pnpm dlx storybook@8 init --builder vite
pnpm add -D @storybook/addon-a11y@8 @storybook/test@8 vitest-axe
```

Follow the **react-ui-package** skill for tokens, component conventions, stories, and the build config.

### `monorepo`

```bash
mkdir my-workspace && cd my-workspace
git init
pnpm init
mkdir -p apps packages
pnpm add -Dw turbo typescript prettier
```

Write the workspace files:

```yaml
# pnpm-workspace.yaml
packages:
  - 'apps/*'
  - 'packages/*'
```

```json
// turbo.json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**", ".next/**", "!.next/cache/**", "storybook-static/**"] },
    "dev": { "cache": false, "persistent": true },
    "lint": { "dependsOn": ["^build"] },
    "typecheck": { "dependsOn": ["^build"] },
    "test": { "dependsOn": ["^build"] },
    "test:coverage": { "dependsOn": ["^build"], "outputs": ["coverage/**"] }
  }
}
```

Root scripts delegate to Turborepo: `"dev": "turbo run dev"`, `"build": "turbo run build"`, `"lint": "turbo run lint"`, `"typecheck": "turbo run typecheck"`, `"test": "turbo run test"`, `"format": "prettier --write ."`. Put a `tsconfig.base.json` at the root and have every package `extends` it. Then scaffold each app with `vite_app` or `next_app` inside `apps/` and each package with `react_package` inside `packages/`. Follow the **react-architecture** skill for package naming and layer rules.

## Post-Scaffold Setup

Every template receives the same baseline. Full file contents are in [references/post-scaffold.md](references/post-scaffold.md).

| File                  | Purpose                                                                                                                          |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `.nvmrc`              | Current Node LTS                                                                                                                 |
| `tsconfig.json`       | `strict`, `noUncheckedIndexedAccess`, `verbatimModuleSyntax`, `@/*` path alias                                                   |
| `eslint.config.js`    | `typescript-eslint` type-checked, `eslint-plugin-react-hooks`, `eslint-plugin-jsx-a11y`, `eslint-plugin-import-x`, Prettier last |
| `.prettierrc`         | Single quotes, trailing commas, 100 columns                                                                                      |
| `vitest.config.ts`    | `jsdom`, setup file, v8 coverage with thresholds                                                                                 |
| `src/test/setup.ts`   | `@testing-library/jest-dom/vitest` matchers and `cleanup` after each test                                                        |
| `src/test/render.tsx` | `renderWithProviders` helper that wraps the tree in the app's providers                                                          |

Dev dependencies installed on every template:

```bash
pnpm add -D typescript @types/node eslint @eslint/js globals typescript-eslint \
  eslint-plugin-react-hooks eslint-plugin-jsx-a11y eslint-plugin-import-x \
  eslint-import-resolver-typescript eslint-config-prettier prettier \
  vitest @vitest/coverage-v8 jsdom @vitejs/plugin-react vite-tsconfig-paths \
  @testing-library/react @testing-library/user-event @testing-library/jest-dom msw
```

Standard scripts on every `package.json`:

| Script          | Command                                        |
| --------------- | ---------------------------------------------- |
| `dev`           | `vite` / `next dev` / `tsup --watch`           |
| `build`         | `tsc -b && vite build` / `next build` / `tsup` |
| `lint`          | `eslint .`                                     |
| `format`        | `prettier --write .`                           |
| `typecheck`     | `tsc --noEmit`                                 |
| `test`          | `vitest run`                                   |
| `test:coverage` | `vitest run --coverage`                        |

## Examples

### User says "Create a new React app called Inventory Tracker"

1. Infer: client-side app, no server signal => `vite_app`; name `inventory-tracker`
2. Nothing missing; no questions
3. Scaffold, apply post-scaffold setup, verify, report `pnpm dev`

### User says "I need a marketing site with a blog"

1. Infer: SEO and content => `next_app`
2. Ask for the project name only
3. Scaffold with `--no-tailwind` unless Tailwind was mentioned; apply setup; verify

### User says "Set up a component library for our design system"

1. Infer: `ui_package`; ask for the package name and npm scope if not given
2. Scaffold `react_package`, add Storybook 8 and `addon-a11y`
3. Hand off to the **react-ui-package** skill for the first component

### User says "Start a monorepo with a web app and a todos API client package"

1. Infer: `monorepo`, then `vite_app` at `apps/web` and `react_package` at `packages/todos-api-client`
2. Ask for the npm scope (for example `@acme`)
3. Scaffold the workspace, then each project; wire `workspace:*` dependencies; verify with `pnpm -r lint test`

### User says "Build something with React"

1. Ambiguous: ask what they are building (app, site, library), not which template
2. Continue from the answer

## Troubleshooting

### `ERR_PNPM_INVALID_PACKAGE_NAME` or "Invalid project name"

- Names must be lowercase kebab-case; convert spaces, underscores, and capitals
- Scoped names must be `@scope/name`

### `create vite` hangs on a prompt

- Pass `--template react-ts`; answer "No" to optional extras; re-run non-interactively with `pnpm create vite my-app --template react-ts --no-interactive` when supported

### ESLint reports "parserOptions.project" or `projectService` errors

- Every linted file must be included by a `tsconfig`; add `vitest.config.ts` and `eslint.config.js` to `tsconfig.json` `include`, or list them under a second config block with `projectService: { allowDefaultProject: [...] }`

### Vitest cannot find `document`

- `environment: 'jsdom'` is missing from `vitest.config.ts`, or `jsdom` was not installed

### `jest-dom` matchers are untyped

- `src/test/setup.ts` must import `@testing-library/jest-dom/vitest` and be included by `tsconfig.json`

### Turborepo runs tasks in the wrong order

- Add `"dependsOn": ["^build"]` so packages build before the apps that consume their `dist`

## Anti-Patterns

| Anti-Pattern                                 | Problem                                                  | Correct Approach                                                       |
| -------------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------- |
| Asking the user to pick a template name      | Users describe what they build, not scaffold identifiers | Infer the template from the description                                |
| Mixing `npm`/`npx` with `pnpm`               | Two lockfiles and a broken `node_modules` layout         | `pnpm`, `pnpm dlx`, and `pnpm create` only                             |
| Keeping the scaffold's default lint config   | Misses type-aware rules, a11y, and import boundaries     | Overwrite with the flat config from `references/post-scaffold.md`      |
| Skipping the test setup                      | First test written later fails on missing matchers       | Install Vitest + Testing Library and write `setup.ts` at scaffold time |
| Leaving `strict` off or `any` allowed        | Type errors surface in production                        | `strict: true`, `noUncheckedIndexedAccess: true`, `no-explicit-any`    |
| Committing `node_modules` or lockfile drift  | Non-reproducible installs                                | `.gitignore` from the scaffold; one `pnpm-lock.yaml` at the root       |
| Unpinned Node or pnpm                        | "Works on my machine" toolchain mismatches               | `.nvmrc`, `engines`, and `packageManager`                              |
| Relative paths between workspace packages    | Breaks when a package moves; bypasses builds             | `"@acme/pkg": "workspace:*"` and import by package name                |
| Scaffolding a data package with `react` deps | Couples a plain TypeScript package to the DOM            | Omit `react`; use `environment: 'node'` in Vitest                      |
