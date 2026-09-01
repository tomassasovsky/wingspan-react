# Wingspan React

Wingspan React is a Claude Code plugin: SDLC workflow skills, React best-practice skills, review agents, and hooks. It ports Very Good Ventures' `vgv-wingspan` (workflow) and `vgv-ai-flutter-plugin` (tech-specific standards) to the React and TypeScript ecosystem. It is a **documentation-and-scripts repository**: there is no application code, only markdown skills, agent definitions, and bash hooks.

## Philosophy

Apply VGV's standards for scalable software to AI-assisted React work. Each step of the development cycle should make the next step clearer and closer to the user's intent. Build the right thing, build the thing right.

## Repository Structure

```text
.claude-plugin/
  plugin.json            # Plugin manifest
  marketplace.json       # Lets this repo act as its own marketplace
.mcp.json                # Context7 MCP server for live documentation
hooks/
  hooks.json             # SessionStart, PostToolUse, and Stop hooks
  scripts/
    common.sh            # Shared helpers (find_up, find_bin, marker file)
    check-toolchain.sh   # SessionStart: warn on missing Node/pnpm/node_modules/jq
    lint.sh              # PostToolUse: eslint --fix on edited JS/TS (exit 2 on errors)
    format.sh            # PostToolUse: prettier --write on edited files (never blocks)
    typecheck.sh         # Stop: tsc --noEmit for packages edited this turn (exit 2 on errors)
    hooks_test.sh        # Test suite for the hooks (fake binaries, no install needed)
scripts/
  validate_plugin_manifest.sh
skills/
  <workflow skills>      # brainstorm, plan, plan-technical-review, refine-approach, build,
                         # review, hotfix, create-pr, rebase, debrief, elements-of-style
  <react skills>         # create-project, architecture, state-management, forms, routing,
                         # testing, accessibility, internationalization, theming, ui-package,
                         # performance, static-security, license-compliance, dependency-upgrade
  shared/                # Canonical references and scripts, symlinked into skills
agents/
  analysis/              # plan-splitting, user-flow-analysis
  codebase-review/       # vgv-review, code-simplicity-review, codebase-review
  quality-review/        # architecture-review, test-quality-review, pr-readiness-review
  research/              # best-practices-research, official-docs-research
config/                  # cspell and markdownlint configuration
```

## Workflow

Four sequential phases, each writing an artifact to `docs/` so the next can start cold:

1. **`/brainstorm`** - explore requirements and approaches. Writes `docs/brainstorm/`.
2. **`/plan`** - turn the brainstorm into an implementation plan with codebase review, research, and flow analysis. Writes `docs/plan/`.
3. **`/build`** - execute the plan: code, tests, surgical-diff gate, five parallel review agents, consolidated report, PR.
4. **`/review`** - run the review agents on demand. Writes `docs/code-review/<slug>/`.

Fast path: **`/hotfix`** skips brainstorm and plan but keeps review and tests.

Standalone: `/debrief`, `/create-pr`, `/rebase`, `/refine-approach`, `/plan-technical-review`, `/elements-of-style`.

**Clear context handoff:** user-invocable skills with a forward transition present "Clear context and [next step]" as the first handoff option. Skills invoked by other skills return control to the caller instead.

## The React Stack These Skills Assume

| Concern        | Default                                                         |
| -------------- | --------------------------------------------------------------- |
| Language       | TypeScript strict, no `any`                                     |
| Package manager| pnpm (workspaces + Turborepo for monorepos)                     |
| Apps           | Vite for SPAs, Next.js App Router for SSR/full-stack            |
| Routing        | React Router v7 data mode, or Next.js file-system routing       |
| Server state   | `@tanstack/react-query`                                         |
| Client state   | `zustand`; `useState`/`useReducer` for local state              |
| Forms          | `react-hook-form` + `zod`                                       |
| Styling        | CSS custom-property tokens; Tailwind v4 `@theme` when present   |
| Tests          | Vitest, Testing Library, `user-event`, `msw`, Playwright        |
| Lint/format    | ESLint 9 flat config, Prettier                                  |
| i18n           | `react-i18next` (Vite) or `next-intl` (Next.js)                 |

Skills detect which of these a project uses from `package.json` and follow the project when it differs. They do not force migrations.

Layered architecture: **Data** (`*-api-client`) → **Domain** (`*-repository`) → **Business logic** (query hooks, stores) → **Presentation** (components, routes, `packages/ui`). Presentation never imports an API client. `packages/ui` imports nothing from data or domain.

## Hooks

Defined in `hooks/hooks.json`. All scripts require `jq` and skip silently without it. Hooks only use tools already installed in the project's `node_modules/.bin`; they never install anything.

| Event        | Script               | Blocking |
| ------------ | -------------------- | -------- |
| SessionStart | `check-toolchain.sh` | No       |
| PostToolUse `Edit\|Write` | `lint.sh` | Yes (exit 2 on ESLint errors) |
| PostToolUse `Edit\|Write` | `format.sh` | No |
| Stop         | `typecheck.sh`       | Yes (exit 2 on `tsc` errors; honors `stop_hook_active`) |

`lint.sh` records each edited package root in a marker file (`$TMPDIR/wingspan-react-typecheck-<hash>`); `typecheck.sh` reads and clears it. Run `bash hooks/scripts/hooks_test.sh` after changing any script.

## Output Directories

- `docs/brainstorm/`, `docs/plan/`, `docs/debriefs/` - user-managed
- `docs/reviews/`, `docs/hotfix-review/` - ephemeral, deleted by the skill that created them
- `docs/code-review/<slug>/` - kept per run of `/review`

## Skill File Format

Every `SKILL.md`:

1. YAML frontmatter: `name` (React skills are prefixed `react-`), `description` (what and when), optional `allowed-tools`, `argument-hint`, `user-invocable`, `when_to_use`, `effort`.
2. H1 title and a one-sentence summary.
3. **Core Standards** first: enforced directives, one line each.
4. Content sections: decision tables, complete TypeScript examples with tests, workflows, and an **Anti-Patterns** table.
5. Long material goes in `references/*.md`, linked from `SKILL.md`. A skill may only link inside its own directory; shared content lives in `skills/shared/` and is symlinked in.

## Writing Conventions

- Directives, not suggestions. "Use X", "Never Y". No "consider" or "prefer".
- Every code block has a language tag. Snippets are complete and typed. No `any`.
- Reference packages by full npm name in backticks.
- Tables over prose. One sentence per rule. Cut anything the body already says.
- Align table pipes (markdownlint MD060).
- No Flutter or Dart references anywhere in React skills or agents.

## Adding a Skill

1. Create `skills/<name>/SKILL.md` (plus `references/` as needed).
2. Add keywords to `.claude-plugin/plugin.json`.
3. Add a row to the matching table in `README.md`.
4. Update the structure listing above.
5. Run `claude plugin validate .` and the CI checks locally (see CONTRIBUTING.md).

## Key Conventions

- **State placement:** server state in TanStack Query, shared client state in zustand, everything else local. Flag deviations.
- **YAGNI:** simplest solution that meets current requirements.
- **Architecture:** respect layer boundaries and dependency direction.
- **Testing:** non-negotiable. Every hook, store, component, route, repository, and client gets a colocated test.

## Commits

Conventional Commits: `type(scope): description`. Examples: `feat: add forms skill`, `fix: lint hook ignores generated files`.
