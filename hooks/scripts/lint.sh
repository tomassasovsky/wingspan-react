#!/bin/bash
# PostToolUse hook: run ESLint (with --fix) on the file Claude just edited.
#
# Exit 2 on remaining lint errors so Claude sees them and fixes them before
# moving on. Skips silently when the file is not a JS/TS source, when the
# project has no ESLint config, or when eslint is not installed locally.
#
# Also records the package root in the typecheck marker so the Stop hook
# knows which projects to typecheck.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

input=$(cat)

if ! command -v jq &>/dev/null; then
  echo "lint hook: jq not found, skipping" >&2
  exit 0
fi

file_path=$(jq -r '.tool_input.file_path // empty' <<< "$input")

if [[ -z "$file_path" || ! -f "$file_path" ]]; then
  exit 0
fi

if [[ ! "$file_path" =~ $SOURCE_FILE_REGEX ]] || is_ignored_path "$file_path"; then
  exit 0
fi

package_root=$(nearest_package_root "$file_path") || exit 0

# Any TS/JS edit inside a package with a tsconfig is a typecheck candidate.
if find_up "$(dirname "$file_path")" "tsconfig.json" >/dev/null; then
  record_touched_root "$package_root"
fi

if ! has_eslint_config "$package_root"; then
  exit 0
fi

eslint_bin=$(find_bin "$package_root" "eslint") || exit 0

# Run from the package root so flat config resolution matches the project.
output=$(cd "$package_root" && "$eslint_bin" --fix --no-warn-ignored --max-warnings=0 "$file_path" 2>&1)
status=$?

if [[ $status -ne 0 ]]; then
  echo "ESLint reported problems in $file_path. Fix them before continuing:" >&2
  echo "$output" >&2
  exit 2
fi

exit 0
