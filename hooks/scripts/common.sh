#!/bin/bash
# Shared helpers for Wingspan React hook scripts.
# shellcheck disable=SC2034  # variables are consumed by the sourcing scripts
#
# Every hook sources this file. Helpers never exit on their own; the
# calling script decides how to react to a missing tool or config.

# Files the lint/format/typecheck hooks care about.
SOURCE_FILE_REGEX='\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$'
FORMAT_FILE_REGEX='\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|json|css|scss|md|mdx|html|yaml|yml)$'

# Marker file that records project roots touched during this session so the
# Stop hook only typechecks projects that actually changed.
typecheck_marker() {
  local hash
  hash=$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | shasum | cut -d' ' -f1)
  printf '%s/wingspan-react-typecheck-%s' "${TMPDIR:-/tmp}" "$hash"
}

# find_up <start-dir> <name>
# Walks up from <start-dir> and prints the first directory containing <name>.
# Prints nothing and returns 1 when no ancestor contains it.
find_up() {
  local dir="$1"
  local name="$2"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -e "$dir/$name" ]]; then
      printf '%s' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  if [[ -e "/$name" ]]; then
    printf '/'
    return 0
  fi
  return 1
}

# find_bin <start-dir> <tool>
# Prints the nearest node_modules/.bin/<tool> above <start-dir>.
find_bin() {
  local dir
  dir=$(find_up "$1" "node_modules/.bin/$2") || return 1
  printf '%s/node_modules/.bin/%s' "$dir" "$2"
}

# nearest_package_root <file>
# Prints the closest ancestor directory containing package.json.
nearest_package_root() {
  find_up "$(dirname "$1")" "package.json"
}

# has_eslint_config <package-root>
# True when the package (or an ancestor) has an ESLint flat or legacy config.
has_eslint_config() {
  local dir="$1"
  local name
  for name in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts eslint.config.mts eslint.config.cts .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yaml .eslintrc.yml; do
    if find_up "$dir" "$name" >/dev/null; then
      return 0
    fi
  done
  return 1
}

# is_ignored_path <file>
# Skip generated, vendored, and build output directories.
is_ignored_path() {
  case "$1" in
    */node_modules/*|*/dist/*|*/build/*|*/.next/*|*/out/*|*/coverage/*|*/.turbo/*|*/storybook-static/*|*.d.ts|*.generated.*|*.gen.*)
      return 0
      ;;
  esac
  return 1
}

# record_touched_root <package-root>
# Appends the root to the typecheck marker (deduplicated).
record_touched_root() {
  local marker
  marker=$(typecheck_marker)
  if [[ -f "$marker" ]] && grep -qxF "$1" "$marker" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$1" >> "$marker"
}
