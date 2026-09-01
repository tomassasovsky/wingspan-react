# Upgrade Checklist

Copy the relevant sections into the PR body and check them off. A box that cannot be checked blocks the merge.

## Pre-Upgrade

- [ ] Current and target versions confirmed with the user for each tool in scope
- [ ] Official migration guide read; codemod commands identified
- [ ] PR sequence agreed: Node, pnpm, TypeScript, framework majors, ESLint, groups of everything else
- [ ] `main` is green: `pnpm install --frozen-lockfile && pnpm typecheck && pnpm lint && pnpm test && pnpm build`
- [ ] Baseline recorded: `pnpm outdated -r --long > upgrade-baseline.txt` (not committed)
- [ ] Branch created per concern (`chore/node-24`, `chore/react-19`, `chore/deps-testing`)

## Per Step

- [ ] Only the packages for this concern changed in `package.json` files (`git diff --stat -- '**/package.json'`)
- [ ] Codemod run before hand edits; its output reviewed file by file
- [ ] `pnpm install` log has no new `peer` or `deprecated` lines, or each one is addressed
- [ ] `pnpm typecheck` green
- [ ] `pnpm lint --max-warnings 0` green
- [ ] `pnpm test` green with coverage thresholds intact
- [ ] `pnpm build` green for every app and package
- [ ] `pnpm exec playwright test` green when e2e exists
- [ ] `pnpm dedupe --check` reports nothing, or `pnpm dedupe` was run and committed
- [ ] Lockfile diff limited to the bumped packages and their transitive closure

## Node Bump Only

- [ ] `.nvmrc`
- [ ] `engines.node` in the root `package.json` and every workspace `package.json` that declares it
- [ ] `node-version-file: .nvmrc` in every CI job
- [ ] `FROM node:<major>-alpine` in every `Dockerfile` and `docker-compose*.yml`
- [ ] `@types/node` major matches
- [ ] Hosting runtime setting updated (Vercel Node version, Lambda runtime, Cloud Run image)
- [ ] Native modules rebuilt and listed in `onlyBuiltDependencies`

## Framework Major Only

- [ ] `react`, `react-dom`, `@types/react`, `@types/react-dom` majors match
- [ ] `@testing-library/react` and `@testing-library/dom` bumped together
- [ ] Deprecation warnings in the browser console and test output triaged
- [ ] Manual smoke test of the three highest-traffic routes in a production build (`pnpm build && pnpm start` or `pnpm preview`)
- [ ] Bundle size compared with the baseline (`pnpm build` output or a size-limit report)

## Post-Upgrade

- [ ] Follow-up issues created for deprecations that were not fixed in this PR
- [ ] `README` or `CONTRIBUTING` updated if the required Node or pnpm version changed
- [ ] Renovate or Dependabot config still targets the new majors (no stale `allowedVersions` pins)
- [ ] `upgrade-baseline.txt` deleted

## PR Body Template

```markdown
## Upgrade: <tool> <from> -> <to>

**Guide:** <link to the official migration guide>
**Codemods run:**
- `npx <codemod command>`

### Changes
- <one line per meaningful hand edit, with the reason>

### Verification
- [ ] `pnpm install --frozen-lockfile` (no new peer warnings)
- [ ] `pnpm typecheck`
- [ ] `pnpm lint --max-warnings 0`
- [ ] `pnpm test`
- [ ] `pnpm build`
- [ ] e2e: <passed | n/a>

### Follow-ups
- <issue link> - <deprecation or warning deferred>

### Rollback
Revert this PR; no data or infrastructure migration is involved.
```

## Rollback Plan

1. Revert the merge commit; the lockfile and manifests return with it.
2. Redeploy the previous build artifact if the runtime (Node major) changed in hosting settings.
3. Re-open the branch with the failing step noted in the PR body before retrying.
