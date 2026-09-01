#!/bin/bash
# PostToolUse hook: run Prettier on the file Claude just edited.
#
# Formatting is applied silently and never blocks - always exits 0. Skips
# when the file type is not one Prettier handles, when the project does not
# have Prettier installed locally, or when the file is Prettier-ignored.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

input=$(cat)

if ! command -v jq &>/dev/null; then
  echo "format hook: jq not found, skipping" >&2
  exit 0
fi

file_path=$(jq -r '.tool_input.file_path // empty' <<< "$input")

if [[ -z "$file_path" || ! -f "$file_path" ]]; then
  exit 0
fi

if [[ ! "$file_path" =~ $FORMAT_FILE_REGEX ]] || is_ignored_path "$file_path"; then
  exit 0
fi

package_root=$(nearest_package_root "$file_path") || exit 0
prettier_bin=$(find_bin "$package_root" "prettier") || exit 0

(cd "$package_root" && "$prettier_bin" --write --ignore-unknown --log-level silent "$file_path") &>/dev/null || true

exit 0
