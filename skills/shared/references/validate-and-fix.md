# Validate and Fix

Run the project's own scripts, in this order. Read `package.json` `scripts` first and use the project's names when they differ from the defaults below. Use the project's package manager (`pnpm` when `pnpm-lock.yaml` exists, `yarn` for `yarn.lock`, otherwise `npm run`).

1. **Lint** - `pnpm lint` (ESLint). Fix every error and warning; `--max-warnings=0` is the bar.
2. **Typecheck** - `pnpm typecheck` (`tsc --noEmit`). Zero errors.
3. **Test** - `pnpm test` (Vitest). For a single package in a monorepo, run it from that package or with `pnpm --filter <package> test`.
4. **Format** - `pnpm format` (Prettier) if the project exposes it; the format hook already handles edited files.

The plugin's hooks run ESLint and Prettier on every edited file and `tsc` before each turn ends, so most problems surface immediately. Still run the full commands before moving on: hooks only cover files you touched.

If failures occur:

- Fix the issue and re-run
- Up to 3 attempts per failure
- After 3 failed attempts, use **AskUserQuestion** to ask the user for guidance with context on what failed and what you tried

Never silence a failure with `eslint-disable`, `@ts-ignore`, `@ts-expect-error`, `.skip`, or a loosened coverage threshold. Fix the cause.
