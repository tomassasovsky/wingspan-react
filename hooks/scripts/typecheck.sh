#!/bin/bash
# Stop hook: run `tsc --noEmit` once per turn for every package Claude edited.
#
# The lint hook records touched package roots in a marker file. When Claude
# is about to stop, this hook typechecks each recorded root. On errors it
# exits 2, which blocks the stop and feeds the compiler output back to Claude
# so the turn continues with a fix. The marker is cleared after every run.
#
# Guard: when `stop_hook_active` is true, a Stop hook already blocked once
# this turn, so exit 0 to avoid an infinite loop.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

input=$(cat)

if ! command -v jq &>/dev/null; then
  exit 0
fi

if [[ "$(jq -r '.stop_hook_active // false' <<< "$input")" == "true" ]]; then
  rm -f "$(typecheck_marker)"
  exit 0
fi

marker=$(typecheck_marker)

if [[ ! -f "$marker" ]]; then
  exit 0
fi

roots=$(sort -u "$marker")
rm -f "$marker"

failures=""

while IFS= read -r root; do
  [[ -n "$root" && -d "$root" ]] || continue

  tsconfig_dir=$(find_up "$root" "tsconfig.json") || continue
  tsc_bin=$(find_bin "$tsconfig_dir" "tsc") || continue

  output=$(cd "$tsconfig_dir" && "$tsc_bin" --noEmit --pretty false -p "$tsconfig_dir/tsconfig.json" 2>&1)
  status=$?

  if [[ $status -ne 0 ]]; then
    failures+="== $tsconfig_dir =="$'\n'"$output"$'\n'
  fi
done <<< "$roots"

if [[ -n "$failures" ]]; then
  echo "TypeScript reported errors in files changed this turn. Fix them before finishing:" >&2
  echo "$failures" >&2
  exit 2
fi

exit 0
