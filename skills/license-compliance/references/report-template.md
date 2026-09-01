# License Compliance Report Template

Fill every placeholder. Delete a section only when its table is empty, and say so in the summary.

```markdown
# License Compliance Report

**Project:** <name> (`<path>`)
**Scope:** production dependencies of `apps/*` and published `packages/*`
**Date:** <YYYY-MM-DD>
**Tools:** `pnpm licenses list --prod --json` (pnpm <version>), `license-checker-rseidelsohn` <version>
**Policy:** allowed = MIT, ISC, BSD-2-Clause, BSD-3-Clause, Apache-2.0, 0BSD, CC0-1.0, Unlicense, BlueOak-1.0.0, Python-2.0

## Summary

| Metric                      | Count |
| --------------------------- | ----- |
| Production packages scanned | <n>   |
| Distinct licenses           | <n>   |
| Compliant (allowed tier)    | <n>   |
| Flagged (manual review)     | <n>   |
| Forbidden                   | <n>   |
| Unknown / guessed / custom  | <n>   |

**Verdict:** <PASS | FAIL> - <one sentence>

## Forbidden

| Package  | Version | License | Direct or transitive (`pnpm why`)   | Recommendation                          |
| -------- | ------- | ------- | ----------------------------------- | --------------------------------------- |
| `<name>` | <x.y.z> | GPL-3.0 | transitive via `<parent>@<version>` | Replace `<parent>` with `<alternative>` |

## Flagged

| Package  | Version | License | Modified? | Usage               | Decision needed                       |
| -------- | ------- | ------- | --------- | ------------------- | ------------------------------------- |
| `<name>` | <x.y.z> | MPL-2.0 | No        | Bundled, unmodified | Approve with source offer, or replace |

## Unknown, Guessed, or Custom

| Package  | Version | Reported | Evidence                              | Action                                   |
| -------- | ------- | -------- | ------------------------------------- | ---------------------------------------- |
| `<name>` | <x.y.z> | MIT*     | `LICENSE` file matches MIT text       | Add clarification with checksum          |
| `<name>` | <x.y.z> | UNKNOWN  | No `license` field, no `LICENSE` file | Open upstream issue; replace in 1 sprint |

## Dual-Licensed Choices

| Package  | Expression            | Chosen |
| -------- | --------------------- | ------ |
| `<name>` | `(MIT OR Apache-2.0)` | MIT    |

## License Distribution

| License      | Packages |
| ------------ | -------- |
| MIT          | <n>      |
| ISC          | <n>      |
| Apache-2.0   | <n>      |
| BSD-3-Clause | <n>      |
| <other>      | <n>      |

## Development-Only Findings (informational)

| Package  | Version | License | Note                         |
| -------- | ------- | ------- | ---------------------------- |
| `<name>` | <x.y.z> | GPL-2.0 | Build tool only; not shipped |

## Recommendations

1. <Most urgent action, with owner and target date>
2. <Next action>
3. Add `pnpm licenses:check` to CI if it is not present (see the skill's CI section).

## Attribution

`THIRD_PARTY_NOTICES.txt` <generated and committed | missing; generate with `pnpm licenses:notices`>.
```

## Commands That Fill the Template

```bash
# Distribution table
jq -r 'to_entries[] | "| \(.key) | \(.value | length) |"' licenses-pnpm.json | sort -t'|' -k3 -rn

# Total production packages
jq '[.[] | length] | add' licenses-pnpm.json

# Distinct licenses
jq 'keys | length' licenses-pnpm.json

# Rows for the Forbidden / Flagged / Unknown tables (name, version, license, licenseFile)
jq -r 'to_entries[]
  | select((.value.licenses | tostring) | test("UNKNOWN|UNLICENSED|SEE LICENSE|\\*|Custom|GPL|LGPL|AGPL|MPL|EPL|SSPL|CC-BY-NC|BUSL"))
  | "| `\(.key | sub("@[^@]+$"; ""))` | \(.key | capture("@(?<v>[^@]+)$").v) | \(.value.licenses) | \(.value.licenseFile // "-") |"' licenses-checker.json

# Dependency chain for one package
pnpm why <name>

# Dev-only findings: everything the full run reports that the --production run does not
pnpm dlx license-checker-rseidelsohn --development --excludePrivatePackages --json --out licenses-dev.json
jq -r 'to_entries[] | select((.value.licenses | tostring) | test("GPL|AGPL|SSPL")) | .key' licenses-dev.json
```
