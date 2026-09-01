# Contributing to Wingspan React

Thank you for taking the time to contribute. Please read this guide before opening a pull request.

## Getting Started

1. **Fork** the repository and clone your fork locally.
2. Create a new branch from `main` for your work.
3. Open the project in your editor of choice. Any text editor works; there is no build step.

## Types of Contributions

| Contribution | Where |
| ------------ | ----- |
| **New skill** | `skills/<skill-name>/SKILL.md` and `skills/<skill-name>/references/` |
| **Improve an existing skill** | Edit the relevant `SKILL.md` or reference file |
| **Agents** | `agents/<category>/<agent-name>.md` |
| **Hooks** | `hooks/scripts/` (add tests to `hooks_test.sh`) |
| **Bug reports and feature requests** | [GitHub Issues](https://github.com/tomassasovsky/wingspan-react/issues) |

## Adding a New Skill

### 1. Create the skill file

Create `skills/<skill-name>/SKILL.md` beginning with YAML frontmatter:

```yaml
---
name: react-<skill-name>
description: What the skill covers. Use when the user asks about X, Y, or Z.
allowed-tools: Read Glob Grep
argument-hint: "[optional hint]"
---
```

| Field | Required | Rules |
| ----- | -------- | ----- |
| `name` | Yes | Lowercase letters, numbers, and hyphens. React skills are prefixed `react-`; workflow skills are not |
| `description` | Yes | What it covers and the phrases that should trigger it |
| `allowed-tools` | No | Space-separated tools the skill may use without prompting |
| `argument-hint` | No | Placeholder shown to the user |
| `user-invocable` | No | `true` for workflow skills the user runs as slash commands |

After the frontmatter:

1. **H1 title** and a one-sentence summary
2. **Core Standards** - enforced constraints, always first
3. **Content sections** - decision tables, complete TypeScript examples with their tests, workflows
4. **Anti-Patterns** table

### 2. Update `plugin.json` keywords

Add relevant keywords to `.claude-plugin/plugin.json`.

### 3. Update the README

Add a row to the React Skills or Workflow Skills table in `README.md`, linking to the `SKILL.md` file.

### 4. Update `CLAUDE.md`

Add the skill to the repository structure listing.

## Skill Writing Guidelines

- **Use clear directives.** "Use X" or "Never Y". No "consider" or "prefer".
- **Fence every code block** with a language identifier (`tsx`, `ts`, `bash`, `json`).
- **Complete, typed, copy-pasteable snippets.** No `any`, no fragments.
- **Reference packages by full npm name** (`@tanstack/react-query`, not "react query").
- **Show the test** for every component, hook, store, or repository you show.
- **Keep prose tight.** Every word in a skill consumes context. Tables over prose, one sentence per rule, no restating in a footer what the body already says.
- **Do not mention Flutter or Dart.** This is a React plugin.

## Shared Resources and Skill Boundaries

A skill can only reference files inside its own directory. Paths that escape the skill folder fail validation with a `reference-exists` error.

When several skills need the same content, store the canonical file in `skills/shared/` and **symlink** it into each skill:

```bash
# From the repo root
ln -s ../../shared/references/validate-and-fix.md skills/build/references/validate-and-fix.md
```

Reference it with the local path in `SKILL.md`:

```markdown
Follow the [validation and fix procedure](references/validate-and-fix.md).
```

The same rule applies to scripts: canonical copies live in `skills/shared/scripts/`, symlinked into `skills/<skill>/scripts/`, and invoked with `${CLAUDE_SKILL_DIR}/scripts/<name>.sh`. Add `Bash(*/scripts/<name>.sh)` to the skill's `allowed-tools`.

Script conventions: `#!/usr/bin/env bash`, `set -euo pipefail`, structured `KEY=value` output on stdout, errors on stderr, exit 1 on failure, `chmod +x`.

## Hooks

Hook scripts live in `hooks/scripts/` and are wired in `hooks/hooks.json`. Rules:

- Read the payload from stdin with `jq`; skip with exit 0 when `jq` is missing.
- Only call tools that exist in the project's `node_modules/.bin`. Never install anything.
- Blocking hooks exit 2 with the problem on stderr. Non-blocking hooks always exit 0.
- Add a test case to `hooks/scripts/hooks_test.sh` for every behavior you add, and run it:

```bash
bash hooks/scripts/hooks_test.sh
```

## Testing Locally

### Prerequisites

- **Claude Code CLI** (`npm install -g @anthropic-ai/claude-code`)
- **jq** on your `PATH`

### Load your local copy

From the repository root:

```bash
claude --plugin-dir .
```

`--plugin-dir` loads the plugin for that session only and overrides any marketplace-installed copy of the same plugin. `${CLAUDE_PLUGIN_ROOT}` resolves to the directory you pass, so hook paths work.

### Verify each component loaded

| Component | How to verify |
| --------- | ------------- |
| **Skills** | Run `/help`. Skills appear as `/wingspan-react:<skill>`. Invoke one to confirm it triggers |
| **Agents** | Ask Claude to "review this with the vgv-review-agent" and confirm it dispatches |
| **Hooks** | In a project with ESLint installed, have Claude edit a `.ts` file with a lint error and confirm the hook reports it |

### Iterate on changes

After editing a `SKILL.md`, an agent, or `hooks/hooks.json`, **restart the `claude --plugin-dir .` session**. Edits to hook `.sh` scripts take effect on the next matching tool call without a restart.

### Rehearse the marketplace install (optional)

```text
/plugin marketplace add /ABSOLUTE/path/to/wingspan-react
/plugin install wingspan-react
```

`.claude-plugin/marketplace.json` in this repo makes it its own marketplace, so the path above is enough.

### Validate before you push

```bash
claude plugin validate .
bash scripts/validate_plugin_manifest.sh
bash hooks/scripts/hooks_test.sh
npx --yes markdownlint-cli2 "**/*.md" "#node_modules" "#CHANGELOG.md" --config config/custom.markdownlint.jsonc
npx --yes cspell --config config/cspell.json "**/*.md" --exclude CHANGELOG.md
```

### Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| Skill missing from `/help` | Invalid frontmatter | Run `claude plugin validate .` and fix the reported error |
| Lint hook never fires | `jq` missing, no ESLint config, or ESLint not installed locally | Install `jq`; add `eslint.config.js`; `pnpm add -D eslint` |
| Typecheck hook never fires | No `tsconfig.json` above the edited file, or `typescript` not installed | Add a `tsconfig.json`; `pnpm add -D typescript` |
| Skill references a file that 404s | Symlink missing or points outside the skill directory | Recreate the symlink per the section above |
| `${CLAUDE_PLUGIN_ROOT}` not resolving | Session not launched via `--plugin-dir` | Restart with `claude --plugin-dir .` from the repo root |

## CI Checks

| Check | What it does | Config |
| ----- | ------------ | ------ |
| Markdown lint | Lints all `*.md` files | `config/custom.markdownlint.jsonc` |
| Spelling | Runs cspell on all `*.md` files | `config/cspell.json` |
| Hook scripts | ShellCheck plus `hooks_test.sh` | `hooks/scripts/` |
| Manifest validation | Validates `plugin.json` and JSON files | `scripts/validate_plugin_manifest.sh` |
| Plugin validation | `claude plugin validate .` | Claude Code CLI |
| Skill validation | Validates changed `SKILL.md` files | `Flash-Brew-Digital/validate-skill@v1` |

If the spelling check flags a legitimate word, add it to the `words` array in `config/cspell.json`.

## Commit Convention

[Conventional Commits](https://www.conventionalcommits.org/): `type(scope): description`.

| Type | When to use | Example |
| ---- | ----------- | ------- |
| `feat` | New skill, agent, or hook | `feat: add forms skill` |
| `fix` | Incorrect guidance or a script bug | `fix: lint hook skips generated files` |
| `docs` | Documentation-only change | `docs: clarify hook prerequisites` |
| `chore` | Maintenance, CI, tooling | `chore: bump markdownlint action` |
| `refactor` | Restructure without changing behavior | `refactor: split testing references` |
| `ci` | CI pipeline changes | `ci: add shellcheck step` |

## Pull Requests

- Branch from `main`.
- Keep PRs focused: **one skill per PR** for new skills.
- Fill out the PR template completely.
- Ensure all CI checks pass before requesting review.
