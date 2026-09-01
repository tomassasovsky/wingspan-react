# Wingspan React

AI-assisted engineering workflows and React best-practice skills for [Claude Code][claude_code_link], modeled on Very Good Ventures' [Wingspan][wingspan_link] and [AI Flutter Plugin][flutter_plugin_link].

Wingspan React is one plugin that does both jobs:

- **Workflow** - a four-phase software development lifecycle (**brainstorm**, **plan**, **build**, **review**) with review agents that write one consolidated, numbered report.
- **React standards** - opinionated skills for architecture, state management, routing, forms, testing, accessibility, internationalization, theming, performance, security, UI packages, license compliance, and dependency upgrades, plus hooks that run ESLint, Prettier, and `tsc` as Claude works.

## Installation

### From this repository's marketplace

One-line install from your terminal:

```bash
claude plugin marketplace add tomassasovsky/wingspan-react && claude plugin install wingspan-react
```

Or inside an active Claude Code session, run these as **two separate commands**:

1. Add the marketplace:

   ```text
   /plugin marketplace add tomassasovsky/wingspan-react
   ```

2. Install the plugin:

   ```text
   /plugin install wingspan-react
   ```

### From a local checkout

```bash
git clone https://github.com/tomassasovsky/wingspan-react.git
claude --plugin-dir ./wingspan-react
```

### Prerequisites

| Tool     | Needed for                                                       |
| -------- | ---------------------------------------------------------------- |
| Node.js  | Everything. Current LTS, ideally pinned with `.nvmrc`            |
| pnpm     | The default package manager in every skill (`corepack enable`)   |
| jq       | Hook payload parsing; hooks skip silently when it is missing     |
| ESLint, Prettier, TypeScript | Installed locally in your project for the hooks to run |

## Getting Started

Wingspan React follows the same four phases as Wingspan. Each phase writes an artifact to `docs/` so the next phase can pick it up from a fresh context window.

### 1. `/brainstorm`

Describe the problem or idea. The bigger and more open-ended, the more value this adds:

```text
/brainstorm how should we add authentication to this app?
```

Output lands in `docs/brainstorm/`.

### 2. `/plan`

Turn the brainstorm into a step-by-step implementation plan:

```text
/plan add email/password and OAuth login using the auth approach from our brainstorm
```

The plan reviews the codebase, references the brainstorm, runs flow analysis, and lands in `docs/plan/`.

### 3. `/build`

Execute the plan: write code and tests, run the surgical-diff gate, run five review agents in parallel, fix what they find, and open a PR:

```text
/build docs/plan/add-authentication.md
```

### 4. `/review`

Run the review agents on demand against a branch, a path, or the whole project:

```text
/review
```

Findings get stable `FINDING-NN` ids so you can act on any of them by number.

### Tips

- **Clear context between phases.** Each phase offers a "Clear context and [next step]" option. Take it.
- **Skip phases when you can.** A small bug fix can go straight to `/build` or `/hotfix`.
- **Skills trigger on their own.** Ask for "a zustand store for the cart" and the state-management skill loads; ask "is this component accessible?" and the accessibility skill loads.

## Workflow Skills

| Skill | Command | Description |
| ----- | ------- | ----------- |
| [**Brainstorm**](skills/brainstorm/SKILL.md) | `/brainstorm <feature or idea>` | Explore requirements and approaches through collaborative dialogue |
| [**Refine Approach**](skills/refine-approach/SKILL.md) | `/refine-approach` | Review and refine brainstorms or plans before proceeding |
| [**Plan**](skills/plan/SKILL.md) | `/plan <feature, bug fix, or improvement>` | Transform brainstorm output into a structured implementation plan |
| [**Plan Technical Review**](skills/plan-technical-review/SKILL.md) | `/plan-technical-review` | Validate that a plan meets requirements and follows best practices |
| [**Build**](skills/build/SKILL.md) | `/build <plan file path>` | Execute a plan: write code and tests, run quality review, ship a PR |
| [**Review**](skills/review/SKILL.md) | `/review [path]` | Run quality review agents on demand and write one consolidated report |
| [**Hotfix**](skills/hotfix/SKILL.md) | `/hotfix <bug description>` | Minimal, targeted fix for emergencies: review and tests without brainstorm or plan |
| [**Create PR**](skills/create-pr/SKILL.md) | `/create-pr` | Validate, commit, push, and open a pull request on GitHub or GitLab |
| [**Rebase**](skills/rebase/SKILL.md) | `/rebase` | Rebase the current feature branch onto the base branch |
| [**Debrief**](skills/debrief/SKILL.md) | `/debrief <incident or context>` | Structured post-incident analysis: timeline, root cause, follow-ups |
| [**Elements of Style**](skills/elements-of-style/SKILL.md) | `/elements-of-style` | Apply Strunk's principles when writing or editing prose |

## React Skills

These load automatically from context. Invoke one directly with `/<skill>` when you want it up front.

| Skill | Description |
| ----- | ----------- |
| [**Create Project**](skills/create-project/SKILL.md) | Scaffold Vite or Next.js apps, libraries, UI packages, and pnpm/Turborepo monorepos with strict TypeScript, ESLint, Prettier, and Vitest wired in |
| [**Architecture**](skills/architecture/SKILL.md) | VGV layered architecture for React: data, domain, business logic, and presentation layers, feature folders, and ESLint-enforced import boundaries |
| [**State Management**](skills/state-management/SKILL.md) | Where state lives: local state, URL state, TanStack Query for server state, zustand for shared client state |
| [**Forms**](skills/forms/SKILL.md) | `react-hook-form` + `zod`: schema-first validation, accessible errors, server error mapping, Server Actions |
| [**Routing**](skills/routing/SKILL.md) | React Router v7 data mode and Next.js App Router: loaders, lazy routes, protected routes, URL state, testing |
| [**Testing**](skills/testing/SKILL.md) | Vitest, Testing Library, `user-event`, `msw`, and Playwright: role queries, provider wrappers, coverage thresholds |
| [**Accessibility**](skills/accessibility/SKILL.md) | WCAG 2.2 A/AA/AAA audits and remediation: semantics, keyboard, focus, contrast, live regions, axe testing |
| [**Internationalization**](skills/internationalization/SKILL.md) | `react-i18next` and `next-intl`: ICU messages, `Intl` formatting, locale routing, RTL with logical properties |
| [**Theming**](skills/theming/SKILL.md) | Design tokens as CSS custom properties, light/dark themes, Tailwind v4 `@theme`, spacing and typography scales |
| [**UI Package**](skills/ui-package/SKILL.md) | Build `packages/ui`: accessible primitives, CVA variants, Storybook, tsup builds, tests for every component |
| [**Performance**](skills/performance/SKILL.md) | Measure first, then code-split, virtualize, defer, and fix waterfalls; Web Vitals targets and React Compiler guidance |
| [**Static Security**](skills/static-security/SKILL.md) | Secrets, cookies, XSS, CSP, redirects, Server Action authorization, supply-chain hygiene, OWASP Top 10 mapping |
| [**License Compliance**](skills/license-compliance/SKILL.md) | Audit npm dependency licenses, categorize them against a policy, and produce a compliance report |
| [**Dependency Upgrade**](skills/dependency-upgrade/SKILL.md) | Upgrade Node, TypeScript, React, Next.js, Vite, and React Router one concern at a time with official codemods |

## Agents

Agents are dispatched by the workflow skills, or on request ("review this with the vgv-review-agent"). Each agent writes a raw report and returns structured findings that the calling skill consolidates.

| Agent | Description |
| ----- | ----------- |
| [**VGV Review**](agents/codebase-review/vgv-review-agent.md) | Reviews React and TypeScript code against VGV standards: hooks rules, state placement, effects, types, a11y, i18n, tests |
| [**Architecture Review**](agents/quality-review/architecture-review-agent.md) | Layer separation, dependency direction, package structure, import boundaries |
| [**Test Quality Review**](agents/quality-review/test-quality-review-agent.md) | Coverage and quality of Vitest, Testing Library, `msw`, and Playwright tests |
| [**Code Simplicity Review**](agents/codebase-review/code-simplicity-review-agent.md) | YAGNI pass: premature memoization, needless stores, over-abstracted props |
| [**PR Readiness Review**](agents/quality-review/pr-readiness-review-agent.md) | Lint, format, typecheck, tests, debug artifacts, lockfile, commit hygiene |
| [**Codebase Review**](agents/codebase-review/codebase-review-agent.md) | Inventories a React repo's structure, tooling, and conventions before planning |
| [**Plan Splitting**](agents/analysis/plan-splitting-agent.md) | Recommends splitting large plans into independently mergeable PRs |
| [**User Flow Analysis**](agents/analysis/user-flow-analysis-agent.md) | Finds flow gaps, edge cases, and missing requirements in specs and plans |
| [**Best Practices Research**](agents/research/best-practices-research-agent.md) | VGV conventions first, then official React ecosystem docs, then industry standards |
| [**Official Docs Research**](agents/research/official-docs-research-agent.md) | Version-specific documentation for frameworks and libraries, via Context7 when available |

## Hooks

| Hook | Trigger | Behavior |
| ---- | ------- | -------- |
| **Check toolchain** (`check-toolchain.sh`) | SessionStart | Warns when Node, pnpm, `node_modules`, or `jq` is missing, or the active Node does not match `.nvmrc`. Non-blocking |
| **Lint** (`lint.sh`) | PostToolUse (`Edit`/`Write`) | Runs the project's local `eslint --fix` on the edited JS/TS file. Exits 2 on remaining problems so Claude fixes them before continuing |
| **Format** (`format.sh`) | PostToolUse (`Edit`/`Write`) | Runs the project's local Prettier on the edited file. Always non-blocking |
| **Typecheck** (`typecheck.sh`) | Stop | Runs `tsc --noEmit` once per turn for every package edited this turn. Exits 2 on errors so the turn continues with a fix |

Hooks only run tools installed in the project (`node_modules/.bin`). They never install anything, and they skip silently when the project has no ESLint config, no Prettier, or no `tsconfig.json`.

Run the hook test suite with:

```bash
bash hooks/scripts/hooks_test.sh
```

## MCP Integration

`.mcp.json` registers the [Context7](https://github.com/upstash/context7) MCP server so research agents and skills can fetch current documentation for React, Next.js, TanStack Query, React Router, Vitest, and other libraries instead of relying on training data.

## Output Directories

| Directory | Written by |
| --------- | ---------- |
| `docs/brainstorm/` | `/brainstorm` |
| `docs/plan/` | `/plan` |
| `docs/reviews/` | `/build` (deleted when the build ships) |
| `docs/hotfix-review/` | `/hotfix` (deleted when the hotfix ships) |
| `docs/code-review/<slug>/` | `/review` (kept for you) |
| `docs/debriefs/` | `/debrief` |

Add these to your project's `.gitignore` unless you want to commit them.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add or improve skills, test changes locally, and open a pull request. Contributors are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Acknowledgements

The workflow skills, agent structure, and repository layout are adapted from [VGV Wingspan][wingspan_link] and the [VGV AI Flutter Plugin][flutter_plugin_link] by [Very Good Ventures][vgv_link], both MIT licensed. This project is not affiliated with or endorsed by Very Good Ventures.

[claude_code_link]: https://claude.ai/code
[wingspan_link]: https://github.com/VeryGoodOpenSource/vgv-wingspan
[flutter_plugin_link]: https://github.com/VeryGoodOpenSource/vgv-ai-flutter-plugin
[vgv_link]: https://verygood.ventures
