---
name: react-license-compliance
description: Audits npm dependency licenses in pnpm projects using pnpm licenses list and license-checker-rseidelsohn, categorizes them as permissive, weak copyleft, strong copyleft, or unknown, applies an allow/flag/forbid policy with production and development scope, handles SPDX expressions, and produces a compliance report with remediation steps and CI enforcement. Use when the user says "check licenses", "license audit", "are our dependencies compliant", "license compliance", "review package licenses", "scan for GPL", "third-party notices", or "pre-release license check".
argument-hint: "[project-directory]"
allowed-tools: Bash Read Glob Grep
---

# License Compliance

Dependency license auditor for pnpm-based React projects: every package that ships in a production bundle or a published library carries a license the policy allows, and the check runs in CI so the answer cannot drift.

---

## Core Standards

Apply these standards to ALL license compliance work:

- **Audit production dependencies with `pnpm licenses list --prod --json`** — it reads the lockfile, so it covers every transitive package that ships
- **Cross-check with `license-checker-rseidelsohn`** — it reads each package's `LICENSE` file and exposes guessed (`*`) and missing licenses that registry metadata hides
- **A missing license is "all rights reserved"** — `UNKNOWN`, third-party `UNLICENSED`, `SEE LICENSE IN ...`, and custom text are flagged, never assumed permissive
- **Transitive dependencies carry the same obligations** — a GPL package three levels deep still binds the bundle
- **Bundling is static linking** — `vite`, `next`, and `tsup` inline dependencies into the output; dynamic-linking exceptions in weak copyleft licenses do not apply
- **Scope by what ships** — `dependencies` of apps and published packages are enforced strictly; `devDependencies` still cannot be unknown
- **Enforce in CI with `--onlyAllow`** — the policy list lives in `package.json`; a new forbidden license fails the pull request
- **Ship attribution** — permissive licenses still require the notice; generate `THIRD_PARTY_NOTICES.txt` in the release build

---

## Tools

| Tool                          | Command                                                    | Strength                                                          |
| ----------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------- |
| `pnpm licenses list`          | `pnpm licenses list --prod --json`                         | Built in, lockfile-accurate, workspace aware                      |
| `license-checker-rseidelsohn` | `pnpm dlx license-checker-rseidelsohn --production --json` | Reads `LICENSE` files, `--onlyAllow`, `--failOn`, clarifications  |
| `license-checker` (fallback)  | `npx license-checker --production --json`                  | Unmaintained original; use only when the fork cannot be installed |

---

## Audit Process

### 1. Collect

```bash
cd "${1:-.}"
pnpm install --frozen-lockfile
pnpm licenses list --prod --json > licenses-pnpm.json
pnpm dlx license-checker-rseidelsohn --production --excludePrivatePackages --json --out licenses-checker.json
```

Monorepo: run both from the workspace root, then run `license-checker-rseidelsohn --start packages/<name>` for each package that is published, because its consumers inherit its `dependencies`.

### 2. Summarize

```bash
# License id -> package count (pnpm output is keyed by license)
jq -r 'to_entries[] | "\(.value | length)\t\(.key)"' licenses-pnpm.json | sort -rn

# Packages whose license is guessed, missing, custom, or copyleft
jq -r 'to_entries[]
  | select((.value.licenses | tostring) | test("UNKNOWN|UNLICENSED|SEE LICENSE|\\*|Custom|GPL|LGPL|AGPL|MPL|EPL|SSPL|CC-BY-NC|BUSL"))
  | "\(.key)\t\(.value.licenses)\t\(.value.licenseFile // "-")"' licenses-checker.json | sort
```

### 3. Categorize and Apply the Policy

Match every distinct license id against the tables below. Resolve SPDX expressions before matching. Record each flagged or forbidden package with its `pnpm why` chain.

### 4. Report

Write the report using [references/report-template.md](references/report-template.md). Lead with forbidden packages, then flagged, then unknown; list compliant packages as a count.

### 5. Remediate and Enforce

Apply the remediation table, then wire the CI check so the result holds.

---

## License Categories

| Category                | Licenses                                                                                              | Risk   | Bundled into a React app                                                |
| ----------------------- | ----------------------------------------------------------------------------------------------------- | ------ | ----------------------------------------------------------------------- |
| Permissive              | MIT, ISC, BSD-2-Clause, BSD-3-Clause, Apache-2.0, 0BSD, CC0-1.0, Unlicense, BlueOak-1.0.0, Python-2.0 | Low    | Ship with attribution; Apache-2.0 also requires the `NOTICE` file       |
| Weak copyleft           | MPL-2.0, LGPL-2.1, LGPL-3.0, EPL-1.0, EPL-2.0, CDDL-1.0                                               | Medium | MPL: keep files unmodified and source available; LGPL/EPL: legal review |
| Strong copyleft         | GPL-2.0, GPL-3.0, AGPL-3.0, SSPL-1.0, EUPL-1.2                                                        | High   | The whole bundle must be released under the same license                |
| Non-commercial / custom | CC-BY-NC-*, BUSL-1.1, Elastic-2.0, `SEE LICENSE IN`, proprietary text                                 | High   | Commercial use restricted; legal review                                 |
| Unknown / none          | `UNKNOWN`, `UNLICENSED`, missing `license` field, `*` suffix (guessed from file)                      | High   | Treat as all rights reserved until clarified                            |

---

## Policy

| Tier      | Licenses                                                                                              | Action                                                        |
| --------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Allowed   | MIT, ISC, BSD-2-Clause, BSD-3-Clause, Apache-2.0, 0BSD, CC0-1.0, Unlicense, BlueOak-1.0.0, Python-2.0 | Pass; include in notices                                      |
| Flagged   | LGPL-2.1, LGPL-3.0, MPL-2.0, EPL-1.0, EPL-2.0, CC-BY-4.0, Artistic-2.0                                | Manual review; record the decision in `licenses/decisions.md` |
| Forbidden | GPL-2.0, GPL-3.0, AGPL-3.0, SSPL-1.0, BUSL-1.1, CC-BY-NC-*, UNKNOWN, third-party UNLICENSED, custom   | Fail; replace, obtain an exception, or drop the package       |

| Scope                                      | Enforcement                                                       |
| ------------------------------------------ | ----------------------------------------------------------------- |
| `dependencies` of apps                     | Allowed only; flagged needs a recorded approval                   |
| `dependencies` of published packages       | Allowed only; flagged is forbidden because consumers inherit it   |
| `optionalDependencies`, `peerDependencies` | Same as `dependencies`                                            |
| `devDependencies`                          | Anything except unknown; a GPL build tool is fine, it never ships |

---

## SPDX Expressions

| Expression                       | Meaning                               | Handling                                                        |
| -------------------------------- | ------------------------------------- | --------------------------------------------------------------- |
| `(MIT OR Apache-2.0)`            | Choose either                         | Pass if any operand is allowed; record the chosen one           |
| `(MIT AND CC-BY-3.0)`            | Both apply                            | Pass only if every operand is allowed                           |
| `Apache-2.0 WITH LLVM-exception` | Base license plus exception           | Evaluate the base license; note the exception                   |
| `GPL-3.0-or-later`, `GPL-3.0+`   | Version range                         | Normalize to the base id before matching the policy             |
| `MIT*`                           | Guessed from `LICENSE` text, no field | Verify the file, then add it to `clarifications.json`           |
| `SEE LICENSE IN LICENSE.txt`     | Custom                                | Read the file; forbidden unless legal approves                  |
| `UNLICENSED`                     | Private, all rights reserved          | Fine for your own workspace packages; forbidden for third-party |

`--onlyAllow` evaluates expressions with `spdx-satisfies`: `OR` passes when any operand is allowed, `AND` only when all are, and `UNKNOWN` or an invalid expression never passes. Clarify guessed licenses once, with a checksum so a changed file re-triggers review:

```json
{
  "some-package@1.2.3": { "licenseName": "MIT", "licenseFile": "LICENSE.md", "checksum": "<sha256 of LICENSE.md>" }
}
```

---

## Remediation

| Situation                                 | Options, in order                                                                                                                                                                    |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Forbidden license in a shipped dependency | Replace with a permissive alternative; check whether another version is dual-licensed; move the usage behind a server API you control (AGPL still applies); buy a commercial license |
| Unknown license                           | Read the repository `LICENSE`; ask the maintainer to add the `license` field; add a clarification with checksum; replace if unresponsive within one sprint                           |
| Flagged weak copyleft                     | Confirm the files are unmodified; MPL: publish the source offer; LGPL/EPL in a minified bundle: legal review or replace                                                              |
| Forbidden license in `devDependencies`    | Allowed; confirm with `pnpm why <pkg>` that nothing in `dependencies` pulls it                                                                                                       |
| Transitive only                           | `pnpm why <pkg>` to find the direct parent; open an issue upstream; `pnpm.overrides` to an API-compatible fork if one exists                                                         |
| Dual license with a forbidden option      | Record the permissive choice in `licenses/decisions.md`; nothing else to do                                                                                                          |

---

## CI Enforcement

```json
{
  "scripts": {
    "licenses:check": "license-checker-rseidelsohn --production --excludePrivatePackages --clarificationsFile licenses/clarifications.json --onlyAllow \"MIT;ISC;BSD-2-Clause;BSD-3-Clause;Apache-2.0;0BSD;CC0-1.0;Unlicense;BlueOak-1.0.0;Python-2.0\"",
    "licenses:notices": "license-checker-rseidelsohn --production --excludePrivatePackages --plainVertical > THIRD_PARTY_NOTICES.txt"
  },
  "devDependencies": {
    "license-checker-rseidelsohn": "4.4.2"
  }
}
```

Approved flagged packages are excluded by exact version so a bump re-triggers review: `--excludePackages "some-mpl-lib@2.1.0"`, with the decision recorded in `licenses/decisions.md`.

```yaml
# .github/workflows/licenses.yml
name: licenses
on:
  pull_request:
    paths: ['package.json', 'pnpm-lock.yaml', '**/package.json', 'licenses/**']
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm licenses:check
      - run: pnpm licenses:notices && git diff --exit-code THIRD_PARTY_NOTICES.txt
```

---

## Anti-Patterns

| Anti-Pattern                                    | Problem                                              | Correct Approach                                                     |
| ----------------------------------------------- | ---------------------------------------------------- | -------------------------------------------------------------------- |
| Auditing without `--production`                 | Build tools inflate the report and hide shipped risk | `--prod` / `--production` for the enforced run; dev scope separately |
| Treating `UNKNOWN` as permissive                | It is all rights reserved                            | Flag, clarify with checksum, or replace                              |
| Approving a flagged package by name only        | The next version can relicense                       | `--excludePackages "name@exact.version"` plus a decision record      |
| Running the audit once before release           | Drift between releases                               | `licenses:check` on every dependency PR                              |
| Assuming LGPL is fine because it is "weak"      | Minified bundles prevent relinking                   | Legal review or replace                                              |
| Publishing `packages/ui` with an MPL dependency | Consumers inherit the obligation                     | Allowed licenses only in published `dependencies`                    |
| Editing `THIRD_PARTY_NOTICES.txt` by hand       | Goes stale on the next install                       | Generate it in CI and diff-check                                     |

---

## Additional Resources

See [references/report-template.md](references/report-template.md) for the complete report template with the summary commands that fill it.
