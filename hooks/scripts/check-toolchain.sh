#!/bin/bash
# SessionStart hook: warn when the Node toolchain the project expects is
# missing. Output is injected into Claude's context. Non-blocking - always
# exits 0.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# Only speak up inside a JavaScript/TypeScript project.
if [[ ! -f "$ROOT/package.json" ]]; then
  exit 0
fi

warnings=()

if ! command -v node &>/dev/null; then
  warnings+=("Node.js is not installed or not on PATH. Install the current LTS (https://nodejs.org) or use nvm/fnm/volta.")
elif [[ -f "$ROOT/.nvmrc" ]]; then
  wanted=$(tr -d 'v[:space:]' < "$ROOT/.nvmrc" | cut -d. -f1)
  actual=$(node --version | tr -d 'v' | cut -d. -f1)
  if [[ -n "$wanted" && "$wanted" =~ ^[0-9]+$ && "$actual" != "$wanted" ]]; then
    warnings+=("Node $actual is active but .nvmrc asks for $wanted. Run 'nvm use' (or the equivalent for your version manager) before installing or running anything.")
  fi
fi

if [[ -f "$ROOT/pnpm-lock.yaml" ]] && ! command -v pnpm &>/dev/null; then
  warnings+=("This project uses pnpm (pnpm-lock.yaml present) but pnpm is not installed. Enable it with 'corepack enable pnpm' or install from https://pnpm.io.")
fi

if [[ -f "$ROOT/yarn.lock" ]] && ! command -v yarn &>/dev/null; then
  warnings+=("This project uses Yarn (yarn.lock present) but yarn is not installed. Enable it with 'corepack enable yarn'.")
fi

if [[ ! -d "$ROOT/node_modules" ]]; then
  if [[ -f "$ROOT/pnpm-lock.yaml" ]]; then
    warnings+=("node_modules is missing. Run 'pnpm install --frozen-lockfile' before linting, typechecking, or testing.")
  elif [[ -f "$ROOT/yarn.lock" ]]; then
    warnings+=("node_modules is missing. Run 'yarn install --immutable' before linting, typechecking, or testing.")
  else
    warnings+=("node_modules is missing. Run 'npm ci' before linting, typechecking, or testing.")
  fi
fi

if ! command -v jq &>/dev/null; then
  warnings+=("jq is not installed. The Wingspan React lint, format, and typecheck hooks skip silently without it. Install with 'brew install jq' or your package manager.")
fi

if [[ ${#warnings[@]} -gt 0 ]]; then
  for w in "${warnings[@]}"; do
    echo "⚠️ $w"
  done
fi

exit 0
