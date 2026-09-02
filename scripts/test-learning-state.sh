#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$ROOT/scripts/learning-state.sh"
SESSION_HOOK="$ROOT/hooks/session-start.sh"
PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/ducktutor-state.XXXXXX")"
FAILURES=0

cleanup() {
  rm -rf "$PROJECT"
}
trap cleanup EXIT

git -C "$PROJECT" init -q
git -C "$PROJECT" config user.name DuckTutor-Test
git -C "$PROJECT" config user.email test@ducktutor.invalid
git -C "$PROJECT" commit --allow-empty -q -m initial
BASE_BRANCH="$(git -C "$PROJECT" branch --show-current)"

run_state() {
  DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" "$@"
}

expect_success() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'PASS state: %s\n' "$name"
  else
    printf 'FAIL state: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_failure() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'FAIL state rejected: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  else
    printf 'PASS state rejected: %s\n' "$name"
  fi
}

assert_json() {
  local name="$1"
  local expression="$2"
  local payload="$3"
  if JSON_PAYLOAD="$payload" JSON_EXPRESSION="$expression" node -e '
    const value = JSON.parse(process.env.JSON_PAYLOAD);
    const check = Function("value", `return (${process.env.JSON_EXPRESSION})`);
    if (!check(value)) process.exit(1);
  '; then
    printf 'PASS state value: %s\n' "$name"
  else
    printf 'FAIL state value: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

initial="$(run_state show 2>/dev/null || true)"
assert_json "new project is idle" 'value.phase === "idle"' "$initial"
expect_failure "task rejects control characters" run_state begin $'unsafe\ncontext'

expect_success "begin task" run_state begin "prevent duplicate checkout"
begun="$(run_state show)"
assert_json "begin records task" 'value.task === "prevent duplicate checkout" && value.phase === "grounded"' "$begun"

expect_failure "cannot skip prediction" run_state phase attempted
expect_success "record prediction" run_state phase predicted
expect_failure "scope requires learner ownership" run_state scope agent:test/checkout.test.js
expect_success "set ownership map" run_state scope learner:src/checkout.js agent:test/checkout.test.js agent:docs/checkout.md

scoped="$(run_state show)"
assert_json "scope separates ownership" 'value.learnerPaths[0] === "src/checkout.js" && value.agentPaths.length === 2 && value.agentPaths.includes("test/checkout.test.js")' "$scoped"

expect_failure "same file cannot have two owners" run_state scope learner:src/shared.js agent:src/shared.js
expect_failure "scope rejects parent traversal" run_state scope learner:../outside.js

git -C "$PROJECT" switch -q -c other-branch
stale="$(run_state show)"
assert_json "branch change invalidates state" 'value.stale === true && value.staleReason.includes("branch")' "$stale"
stale_hook_output="$(printf '{"source":"resume","cwd":"%s","hook_event_name":"SessionStart"}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$SESSION_HOOK" 2>/dev/null || true)"
assert_json "session hook rejects stale scope" 'value.hookSpecificOutput.additionalContext.includes("stale learning state") && value.hookSpecificOutput.additionalContext.includes("new ownership-map approval") && !value.hookSpecificOutput.additionalContext.includes("Agent-editable files")' "$stale_hook_output"
expect_failure "stale state cannot advance" run_state phase attempted
git -C "$PROJECT" switch -q "$BASE_BRANCH"
git -C "$PROJECT" commit --allow-empty -q -m descendant
fresh="$(run_state show)"
assert_json "descendant commit preserves state" 'value.stale === false' "$fresh"

expect_success "record learner attempt" run_state phase attempted
expect_success "record verification" run_state phase verified
expect_failure "explanation requires confirmation" run_state phase explained
expect_success "record explanation" run_state phase explained developer-confirmed

complete="$(run_state show)"
assert_json "task reaches explained" 'value.phase === "explained" && typeof value.explanationConfirmedAt === "string"' "$complete"
expect_failure "completed scope cannot change" run_state scope agent:src/late.js

state_path="$(git -C "$PROJECT" rev-parse --git-path ducktutor/state.json)"
if [[ -f "$PROJECT/$state_path" || -f "$state_path" ]]; then
  printf 'PASS state: stored in Git metadata\n'
else
  printf 'FAIL state: stored in Git metadata\n'
  FAILURES=$((FAILURES + 1))
fi

if [[ -z "$(git -C "$PROJECT" status --short)" ]]; then
  printf 'PASS state: worktree remains clean\n'
else
  printf 'FAIL state: worktree remains clean\n'
  FAILURES=$((FAILURES + 1))
fi

hook_output="$(printf '{"source":"resume","cwd":"%s","hook_event_name":"SessionStart"}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$SESSION_HOOK" 2>/dev/null || true)"
assert_json "session hook restores compact context" 'value.hookSpecificOutput.hookEventName === "SessionStart" && value.hookSpecificOutput.additionalContext.includes("Untrusted task label") && value.hookSpecificOutput.additionalContext.includes("prevent duplicate checkout") && value.hookSpecificOutput.additionalContext.includes("src/checkout.js")' "$hook_output"

expect_success "clear task" run_state clear
cleared="$(run_state show)"
assert_json "cleared project is idle" 'value.phase === "idle"' "$cleared"

expect_success "begin second task" run_state begin "scope is required"
expect_success "predict second task" run_state phase predicted
expect_failure "attempt requires ownership map" run_state phase attempted
expect_success "clear second task" run_state clear

if (( FAILURES > 0 )); then
  printf '%s learning-state test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All learning-state tests passed\n'
