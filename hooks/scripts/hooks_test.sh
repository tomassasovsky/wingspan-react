#!/bin/bash
# Tests for the Wingspan React hook scripts.
#
# Usage: bash hooks/scripts/hooks_test.sh
#
# Builds a throwaway project in a temp directory with fake `eslint`,
# `prettier`, and `tsc` binaries under node_modules/.bin so the hooks can be
# exercised without installing anything. Each fake records its invocation
# and exits with a configurable status.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PROJECT="$TMP/project"
BIN="$PROJECT/node_modules/.bin"
LOG="$TMP/calls.log"
mkdir -p "$BIN" "$PROJECT/src" "$PROJECT/dist"
: > "$LOG"

export CLAUDE_PROJECT_DIR="$PROJECT"
export TMPDIR="$TMP"

fake_tool() {
  local name="$1"
  local status="$2"
  cat > "$BIN/$name" <<EOF
#!/bin/bash
echo "$name \$*" >> "$LOG"
if [[ "$status" != "0" ]]; then
  echo "$name: simulated failure"
  exit $status
fi
EOF
  chmod +x "$BIN/$name"
}

echo '{"name":"fixture"}' > "$PROJECT/package.json"
echo '{}' > "$PROJECT/tsconfig.json"
echo 'export default [];' > "$PROJECT/eslint.config.js"
echo 'export const a = 1;' > "$PROJECT/src/a.ts"
echo 'export const b = 1;' > "$PROJECT/dist/b.js"
echo '# readme' > "$PROJECT/README.md"

PASSED=0
FAILED=0

pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; PASSED=$((PASSED + 1)); }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAILED=$((FAILED + 1)); }

# run_hook <script> <file_path> [extra-json]
# Prints the exit status.
run_hook() {
  local script="$1"
  local file="$2"
  local extra="${3:-}"
  [[ -z "$extra" ]] && extra='{}'
  local payload
  payload=$(jq -n --arg f "$file" --argjson x "$extra" '{tool_input:{file_path:$f}} + $x')
  set +e
  echo "$payload" | bash "$SCRIPT_DIR/$script" >/dev/null 2>&1
  local status=$?
  set -e
  echo "$status"
}

called() { grep -q "^$1" "$LOG"; }
reset_log() { : > "$LOG"; }
marker() { printf '%s/wingspan-react-typecheck-%s' "$TMPDIR" "$(printf '%s' "$CLAUDE_PROJECT_DIR" | shasum | cut -d' ' -f1)"; }

echo "=== lint.sh ==="
fake_tool eslint 0; fake_tool prettier 0; fake_tool tsc 0
reset_log; rm -f "$(marker)"

s=$(run_hook lint.sh "$PROJECT/src/a.ts")
if [[ "$s" == "0" ]] && called "eslint --fix"; then pass "runs eslint on a .ts file and exits 0 when clean"; else fail "eslint clean run (status $s)"; fi
if [[ -f "$(marker)" ]] && grep -qxF "$PROJECT" "$(marker)"; then pass "records the package root for typecheck"; else fail "typecheck marker not recorded"; fi

reset_log
s=$(run_hook lint.sh "$PROJECT/README.md")
if [[ "$s" == "0" ]] && ! called "eslint"; then pass "skips non-source files"; else fail "should skip README.md"; fi

reset_log
s=$(run_hook lint.sh "$PROJECT/dist/b.js")
if [[ "$s" == "0" ]] && ! called "eslint"; then pass "skips build output directories"; else fail "should skip dist/"; fi

fake_tool eslint 1
reset_log
s=$(run_hook lint.sh "$PROJECT/src/a.ts")
if [[ "$s" == "2" ]]; then pass "exits 2 when eslint reports errors"; else fail "expected exit 2 on eslint failure, got $s"; fi

rm "$PROJECT/eslint.config.js"
fake_tool eslint 1
reset_log
s=$(run_hook lint.sh "$PROJECT/src/a.ts")
if [[ "$s" == "0" ]] && ! called "eslint"; then pass "skips when the project has no eslint config"; else fail "should skip without eslint config"; fi
echo 'export default [];' > "$PROJECT/eslint.config.js"

echo ""
echo "=== format.sh ==="
fake_tool prettier 1
reset_log
s=$(run_hook format.sh "$PROJECT/src/a.ts")
if [[ "$s" == "0" ]] && called "prettier --write"; then pass "runs prettier and never blocks"; else fail "prettier run (status $s)"; fi

reset_log
s=$(run_hook format.sh "$PROJECT/README.md")
if [[ "$s" == "0" ]] && called "prettier --write"; then pass "formats markdown too"; else fail "should format README.md"; fi

reset_log
s=$(run_hook format.sh "$PROJECT/src/a.png")
if [[ "$s" == "0" ]] && ! called "prettier"; then pass "skips unsupported file types"; else fail "should skip .png"; fi

echo ""
echo "=== typecheck.sh ==="
fake_tool tsc 0
reset_log; rm -f "$(marker)"
s=$(run_hook typecheck.sh "" '{}')
if [[ "$s" == "0" ]] && ! called "tsc"; then pass "does nothing when no files were touched"; else fail "should skip without marker"; fi

run_hook lint.sh "$PROJECT/src/a.ts" >/dev/null
reset_log
s=$(run_hook typecheck.sh "" '{}')
if [[ "$s" == "0" ]] && called "tsc --noEmit"; then pass "runs tsc for touched roots and exits 0 when clean"; else fail "tsc clean run (status $s)"; fi
if [[ ! -f "$(marker)" ]]; then pass "clears the marker after running"; else fail "marker should be cleared"; fi

fake_tool tsc 2
run_hook lint.sh "$PROJECT/src/a.ts" >/dev/null
reset_log
s=$(run_hook typecheck.sh "" '{}')
if [[ "$s" == "2" ]]; then pass "exits 2 when tsc reports errors"; else fail "expected exit 2 on tsc failure, got $s"; fi

run_hook lint.sh "$PROJECT/src/a.ts" >/dev/null
reset_log
s=$(run_hook typecheck.sh "" '{"stop_hook_active":true}')
if [[ "$s" == "0" ]] && ! called "tsc"; then pass "does not re-run when stop_hook_active is true"; else fail "should honor stop_hook_active"; fi

echo ""
echo "=== check-toolchain.sh ==="
out=$(cd "$PROJECT" && rm -rf node_modules && bash "$SCRIPT_DIR/check-toolchain.sh" </dev/null)
if echo "$out" | grep -q "node_modules is missing"; then pass "warns when node_modules is missing"; else fail "missing node_modules warning"; fi
mkdir -p "$BIN"
out=$(cd "$TMP" && bash "$SCRIPT_DIR/check-toolchain.sh" </dev/null)
if [[ -z "$out" ]]; then pass "stays silent outside a JS project"; else fail "should be silent outside JS project"; fi

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[[ "$FAILED" -eq 0 ]]
