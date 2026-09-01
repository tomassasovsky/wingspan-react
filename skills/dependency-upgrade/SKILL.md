---
name: react-dependency-upgrade
description: Upgrades Node.js, TypeScript, React, Next.js or Vite, React Router, ESLint, and general npm dependencies in pnpm projects, one concern per pull request, using official migration guides and codemods before hand edits. Use when the user says "upgrade React", "bump Node", "update Next.js", "migrate to React 19", "update dependencies", "pnpm outdated", "upgrade TypeScript", "move to ESLint 9", "fix peer dependency warnings", or "prep the upgrade PR".
argument-hint: "[package-or-tool] [target-version]"
allowed-tools: Bash Read Edit Glob Grep
---

# Dependency Upgrade

One concern per pull request, the official codemod before any hand edit, and a green `typecheck && lint && test && build` after every step.

---

## Core Standards

Apply these standards to ALL upgrade work:

- **One concern per PR** — Node bump, then TypeScript, then framework majors (React, Next.js or Vite, React Router), then everything else; never combine two majors
- **Read the official migration guide and run the official codemod first** — `npx @next/codemod@latest upgrade latest`, `npx codemod@latest react/19/migration-recipe`, `npx types-react-codemod@latest preset-19 ./src`; hand edits cover only what the codemod leaves
- **Move Node everywhere at once** — `.nvmrc`, `engines.node`, CI `node-version-file`, `Dockerfile` base image, and the `@types/node` major land in the same commit
- **Use `pnpm up --interactive --latest` for minors and patches** — review the list, group by area, and keep majors out of that PR
- **Verify after each step** — `pnpm install && pnpm typecheck && pnpm lint && pnpm test && pnpm build`; a red step is fixed or reverted before the next one starts
- **Read every peer dependency warning** — `pnpm install` output plus `pnpm why <pkg>` decide whether a plugin needs a bump too
- **Update `@types/*` alongside the runtime package** — `@types/react` and `@types/react-dom` majors match React; `@types/node` matches Node
- **Regenerate the lockfile only intentionally** — CI installs with `--frozen-lockfile`; deleting `pnpm-lock.yaml` happens only in a dedicated lockfile-maintenance PR
- **Pin the package manager** — `"packageManager": "pnpm@10.x.y"` in the root `package.json` so every machine and CI runner resolves the same tree
- **Confirm targets before editing** — state the current and target version of each tool and get agreement before touching files

---

## Workflow

### 0. Inventory

```bash
node -v && pnpm -v && cat .nvmrc
jq '{engines, packageManager}' package.json
ls next.config.* vite.config.* eslint.config.* .eslintrc* 2>/dev/null
pnpm outdated -r --long
rg -n "node-version|node:|FROM node" .github/workflows Dockerfile* docker-compose*.yml 2>/dev/null
```

Detect the framework, list every major behind, and propose the PR sequence to the user.

### 1. Node

```bash
echo "24" > .nvmrc
pnpm pkg set engines.node=">=24.0.0 <25"
pnpm up -r @types/node@24
sed -i '' 's/FROM node:22[^ ]*/FROM node:24-alpine/' Dockerfile
rg -n "node-version" .github/workflows   # every job uses `node-version-file: .nvmrc`
pnpm install && pnpm rebuild && pnpm typecheck && pnpm test && pnpm build
```

### 2. pnpm

```bash
pnpm self-update                     # or: corepack use pnpm@latest
pnpm pkg set packageManager="pnpm@$(pnpm -v)"
pnpm install --frozen-lockfile        # confirm the lockfile still resolves
```

### 3. TypeScript

```bash
pnpm up -r typescript@latest typescript-eslint@latest
pnpm typecheck && pnpm lint
```

Read the TypeScript release notes for new checks; fix the code, never loosen `strict` or `noUncheckedIndexedAccess`. A `typescript-eslint` warning about an unsupported TypeScript range means `typescript-eslint` moves first.

### 4. Framework Majors

| Framework    | Commands                                                                                                                                                                        | Guide                                                     |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| React 19     | `pnpm up -r react@19 react-dom@19 @types/react@19 @types/react-dom@19` then `npx codemod@latest react/19/migration-recipe` and `npx types-react-codemod@latest preset-19 ./src` | [references/react-19.md](references/react-19.md)          |
| Next.js      | `npx @next/codemod@latest upgrade latest` (bumps `next`, `react`, `react-dom`, `eslint-config-next`, runs codemods)                                                             | Official upgrade guide for the target major               |
| Vite         | `pnpm up -r vite@latest @vitejs/plugin-react@latest vitest@latest @vitest/coverage-v8@latest`                                                                                   | Vite migration guide; Vitest major follows Vite major     |
| React Router | Enable every `future` flag on v6, fix warnings, then `pnpm up -r react-router@7` and `pnpm remove react-router-dom`                                                             | React Router v7 upgrade guide; import from `react-router` |

### 5. ESLint 9 Flat Config

```bash
npx @eslint/migrate-config .eslintrc.json   # produces eslint.config.mjs as a starting point
pnpm up -r eslint@latest typescript-eslint@latest eslint-plugin-react-hooks@latest eslint-plugin-jsx-a11y@latest eslint-plugin-import-x@latest
git rm .eslintrc* .eslintignore
pnpm lint --max-warnings 0
```

Convert the generated file to `eslint.config.ts` with `tseslint.config()`, plugin flat exports (`reactHooks.configs['recommended-latest']`, `jsxA11y.flatConfigs.recommended`, `importX.flatConfigs.typescript`), and an `ignores` block replacing `.eslintignore`. Next.js 16 exports flat configs from `eslint-config-next` directly and no longer ships `next lint`; the `lint` script calls `eslint .`.

### 6. Everything Else

```bash
pnpm up -r --interactive --latest   # select one group at a time
pnpm dedupe
pnpm install --frozen-lockfile
```

Groups: testing (`vitest`, `@testing-library/*`, `msw`, `@playwright/test`), data (`@tanstack/react-query`, `zustand`, `zod`, `react-hook-form`), styling (`tailwindcss`), tooling (`prettier`, `storybook`, `turbo`). A group with a major inside gets its own PR.

### 7. Verify

```bash
pnpm install --frozen-lockfile 2>&1 | tee install.log
rg -in "peer|deprecated" install.log
pnpm typecheck && pnpm lint && pnpm test && pnpm build
pnpm exec playwright test            # when e2e exists
git diff --stat pnpm-lock.yaml       # a few hundred lines per group, not thousands
```

---

## What to Check per Tool

| Tool            | Versions live in                                                | Check after the bump                                                                                                         |
| --------------- | --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Node            | `.nvmrc`, `engines`, CI, `Dockerfile`, `@types/node`            | `node -v` in CI logs, native modules rebuilt (`pnpm rebuild`), `onlyBuiltDependencies` still lists them                      |
| pnpm            | `packageManager`, `pnpm/action-setup`                           | `lockfileVersion` unchanged or intentionally bumped, settings moved from `.npmrc` to `pnpm-workspace.yaml` on v10            |
| TypeScript      | `typescript`, `typescript-eslint`, `@types/*`                   | New strictness flags, `moduleResolution: bundler`, `erasableSyntaxOnly` if enabled, `tsc -b` for project references          |
| React           | `react`, `react-dom`, `@types/react*`, `@testing-library/react` | [references/react-19.md](references/react-19.md); `act` import, ref cleanup, `useActionState`, StrictMode double effects     |
| Next.js         | `next`, `eslint-config-next`, `@next/codemod`                   | Async `params`/`cookies()`/`headers()`, fetch caching defaults, `middleware.ts` to `proxy.ts`, Turbopack config, `next lint` |
| Vite            | `vite`, `@vitejs/plugin-react`, `vitest`                        | Node floor (Vite 7: 20.19+ or 22.12+), `build.target` default, Environment API plugin changes, `vitest` major alignment      |
| React Router    | `react-router` (drop `react-router-dom`)                        | All `future` flags true first, `json()`/`defer()` removed (return plain objects), route module typegen in framework mode     |
| ESLint          | `eslint`, `typescript-eslint`, every `eslint-plugin-*`          | Flat config only, `eslint --print-config src/App.tsx` shows expected rules, `--max-warnings 0` still passes                  |
| TanStack Query  | `@tanstack/react-query`, `@tanstack/eslint-plugin-query`        | v5: object-only signatures, `isPending`, `gcTime`, `useSuspenseQuery`, removed `onSuccess` callbacks on `useQuery`           |
| Testing Library | `@testing-library/react`, `/dom`, `/jest-dom`, `/user-event`    | `@testing-library/dom` is a peer since v16, `renderHook` from `/react`, `vitest` `setupFiles` still registers `jest-dom`     |
| Tailwind        | `tailwindcss`, `@tailwindcss/vite` or `@tailwindcss/postcss`    | `npx @tailwindcss/upgrade` for v4, `@theme` replaces `tailwind.config.js`, `@import "tailwindcss"` in the entry CSS          |
| Storybook       | `storybook`, `@storybook/react-vite`                            | `npx storybook@latest upgrade`, consolidated `storybook` package, addon renames, `main.ts` framework field                   |
| Playwright      | `@playwright/test`                                              | `pnpm exec playwright install --with-deps` in CI after every bump; browser binaries change with the package                  |

---

## Troubleshooting

| Symptom                                           | Cause                                                   | Fix                                                                                                                       |
| ------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `ERR_PNPM_PEER_DEP_ISSUES` or unmet peer warning  | Plugin does not yet support the new major               | Bump the plugin; if no release exists, add `pnpm.peerDependencyRules.allowedVersions` with a comment and a tracking issue |
| `Invalid hook call` or two React copies           | Duplicate `react` in the lockfile after the bump        | `pnpm why react`, `pnpm dedupe`, then `pnpm.overrides.react` if a dependency pins an old range                            |
| Types for `react/jsx-runtime` missing             | `@types/react` behind `react`                           | Align `@types/react` and `@types/react-dom` majors with `react`                                                           |
| New `TS2322`/`TS2345` errors after the TS bump    | Stricter inference in the new compiler                  | Fix the types; never loosen `strict`                                                                                      |
| ESLint reports no config found                    | ESLint 9 ignores `.eslintrc*`                           | Migrate to `eslint.config.ts`                                                                                             |
| `fetch is not defined` or `AbortSignal.any` error | CI Node older than `.nvmrc`                             | Every job uses `node-version-file: .nvmrc`                                                                                |
| Vitest fails to start after the Vite bump         | Vitest major behind Vite major                          | Bump `vitest` and `@vitest/*` to the matching major                                                                       |
| `sharp` or `esbuild` fails to load                | Node major changed the prebuilt binary ABI              | `pnpm rebuild`; confirm `onlyBuiltDependencies` includes them                                                             |
| Lockfile diff is thousands of lines               | Accidental full re-resolve                              | `git checkout pnpm-lock.yaml`, then `pnpm up <pkg>` for the intended packages only                                        |
| Next.js `params` or `searchParams` type errors    | Request APIs are Promises since Next.js 15              | `await params`; `npx @next/codemod@latest next-async-request-api`                                                         |
| Hydration mismatch after React 19                 | Nondeterministic render (`Date.now()`, `Math.random()`) | Move the value to state set in `useEffect`; `suppressHydrationWarning` only on the single node that must differ           |
| `pnpm install` rewrites `packageManager`          | Corepack and pnpm versions disagree                     | Pin `packageManager` once; run `corepack use pnpm@<version>` on every machine                                             |

---

## PR Checklist

- [ ] PR touches one concern; the title names the tool and the version (`chore(deps): bump Node to 24`)
- [ ] Official migration guide linked in the PR body; codemod commands listed
- [ ] `.nvmrc`, `engines`, CI, and `Dockerfile` agree (Node PRs)
- [ ] `pnpm install --frozen-lockfile` passes in CI; lockfile diff is limited to the bumped packages
- [ ] No new peer dependency warnings in the install log
- [ ] `pnpm typecheck && pnpm lint --max-warnings 0 && pnpm test && pnpm build` green
- [ ] Deprecation warnings introduced by the bump are fixed or listed as follow-up issues
- [ ] Rollback plan stated (revert commit; no data migrations involved)

See [references/checklist.md](references/checklist.md) for the full pre-upgrade, per-step, and post-upgrade checklist with the PR body template.

---

## Anti-Patterns

| Anti-Pattern                                            | Problem                                          | Correct Approach                                            |
| ------------------------------------------------------- | ------------------------------------------------ | ----------------------------------------------------------- |
| `pnpm up -r --latest` in one commit                     | Dozens of majors, impossible to bisect           | One concern per PR; `--interactive` and pick a group        |
| Hand-editing `forwardRef` call sites before the codemod | Slow, inconsistent, misses files                 | `npx codemod@latest react/19/migration-recipe` first        |
| Bumping `.nvmrc` but not the `Dockerfile`               | Production runs a different Node than CI         | Change all Node locations in one commit                     |
| Deleting `pnpm-lock.yaml` to "fix" a conflict           | Silent upgrades of every transitive dependency   | Resolve the conflict in `package.json`, then `pnpm install` |
| `peerDependencyRules.ignoreMissing: true` globally      | Hides real incompatibilities forever             | Targeted `allowedVersions` with a comment and an issue      |
| Suppressing new type errors with `// @ts-expect-error`  | Debt that blocks the next upgrade                | Fix the type; if impossible, an issue and a dated comment   |
| Skipping `pnpm build` because tests pass                | Bundler and SSR issues appear only at build time | `build` is part of every verification step                  |
| Upgrading `vite` without `vitest`                       | Vitest breaks on the new Vite internals          | Bump both in the same PR                                    |
| Loosening `strict` to make a TS upgrade pass            | Loses guarantees the codebase depends on         | Fix the code, keep the flags                                |
