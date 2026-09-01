# Supply Chain Reference

## pnpm Settings

pnpm 10 reads its settings from `pnpm-workspace.yaml` and skips dependency lifecycle scripts by default. Keep both of those behaviors and add a release-age gate.

```yaml
# pnpm-workspace.yaml
packages:
  - apps/*
  - packages/*

# Ignore versions published less than 24 hours ago (minutes). Most malicious releases are pulled within hours.
minimumReleaseAge: 1440
minimumReleaseAgeExclude:
  - '@my-org/*'

# Lifecycle scripts stay off for everything except packages that genuinely need a native build step.
onlyBuiltDependencies:
  - esbuild
  - sharp
```

```ini
# .npmrc
save-exact=true
engine-strict=true
```

```json
{
  "packageManager": "pnpm@10.18.0",
  "engines": { "node": ">=24.0.0 <25", "pnpm": ">=10.16.0" },
  "pnpm": {
    "overrides": {
      "lodash@<4.17.21": ">=4.17.21"
    },
    "auditConfig": {
      "ignoreGhsas": []
    }
  }
}
```

Every entry in `overrides` and `auditConfig.ignoreGhsas` carries a comment in the adjacent `SECURITY.md` or a tracking issue link; an ignore without a justification is a finding.

## Audit and Scan

```bash
pnpm install --frozen-lockfile
pnpm audit --audit-level=high                                            # non-zero exit on high/critical
pnpm audit --fix                                                         # writes overrides into package.json; review the diff
osv-scanner --lockfile=pnpm-lock.yaml                                    # exits non-zero on any known CVE
osv-scanner --lockfile=pnpm-lock.yaml --format=sarif --output=osv.sarif  # upload to GitHub code scanning
pnpm outdated --long                                                     # patches that may carry unannounced fixes
```

Install `osv-scanner` with `brew install osv-scanner` locally; CI uses the reusable workflow below. Ignore a finding only in `osv-scanner.toml` with a reason and an expiry:

```toml
# osv-scanner.toml
[[IgnoredVulns]]
id = "GHSA-xxxx-xxxx-xxxx"
ignoreUntil = 2026-12-31
reason = "Affected function is never called; tracked in ISSUE-123"
```

## CI Workflow

```yaml
# .github/workflows/security.yml
name: security

on:
  pull_request:
  schedule:
    - cron: '0 6 * * 1'

permissions:
  contents: read
  security-events: write
  actions: read

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm audit --audit-level=high

  osv:
    uses: google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@v2
    with:
      scan-args: |-
        --lockfile=pnpm-lock.yaml
```

Pin third-party actions to a commit SHA (`actions/checkout@<sha> # v4.2.2`) once the workflow is stable; Renovate's `helpers:pinGitHubActionDigests` preset keeps them current.

## Renovate

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended", ":pinAllExceptPeerDependencies", "helpers:pinGitHubActionDigests"],
  "minimumReleaseAge": "3 days",
  "lockFileMaintenance": { "enabled": true, "schedule": ["before 6am on monday"] },
  "packageRules": [
    {
      "matchUpdateTypes": ["minor", "patch"],
      "matchCurrentVersion": "!/^0/",
      "groupName": "non-major dependencies",
      "automerge": true
    },
    {
      "matchPackageNames": ["react", "react-dom", "next", "vite", "typescript", "@types/react", "@types/react-dom"],
      "groupName": "framework",
      "automerge": false
    }
  ],
  "vulnerabilityAlerts": { "labels": ["security"], "minimumReleaseAge": null }
}
```

## Dependabot

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: npm
    directory: /
    schedule:
      interval: weekly
    cooldown:
      default-days: 3
    groups:
      non-major:
        update-types: [minor, patch]
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

## Provenance and Integrity

- Publish workspace packages with provenance: `pnpm publish --provenance` in a GitHub Actions job with `permissions: id-token: write`; consumers can verify the build on npmjs.com.
- Prefer dependencies that show the Provenance badge on npmjs.com; for critical packages, compare the linked source commit with the published tarball (`pnpm view <pkg> dist.tarball`, unpack, diff).
- Add Subresource Integrity to any third-party `<script src>` that cannot be self-hosted: `integrity="sha384-..." crossorigin="anonymous"`; generate with `openssl dgst -sha384 -binary file.js | openssl base64 -A`.
- Keep `pnpm-lock.yaml` committed and install with `--frozen-lockfile`; a lockfile change in a PR that did not touch `package.json` is a finding.

## Typosquatting and Install Scripts

Flag a package that matches any of these signals:

- Name differs from a popular package by one character, a swapped separator, or transposed letters (`react-dorn`, `lodahs`, `cross-env-shell`).
- Published less than six months ago, with low weekly downloads, and requested by a new direct dependency.
- Declares `preinstall`, `install`, or `postinstall` scripts that touch the network or the filesystem outside its own directory.
- Maintainer changed in the last release, or the version jumped several majors at once.
- Repository URL in `package.json` does not match the npm publisher.

```bash
pnpm why <pkg>                                   # who pulls it in
pnpm ls --depth Infinity --json | jq -r '..|.name? // empty' | sort -u | wc -l

# Every package in the store that declares an install script
find node_modules/.pnpm -maxdepth 5 -name package.json \
  -exec jq -r 'select(.scripts.preinstall or .scripts.install or .scripts.postinstall)
    | "\(.name)@\(.version)\t\(.scripts.postinstall // .scripts.install // .scripts.preinstall)"' {} + | sort -u
```

Any name on that list that is not in `onlyBuiltDependencies` is running nothing; any name that is on the list gets its script read before approval.
