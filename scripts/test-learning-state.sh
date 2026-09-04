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
assert_json "new project defaults to quiz mode" 'value.phase === "idle" && value.schema === 4 && value.responseMode === "quiz" && !value.deepReflectionRequired' "$initial"
expect_failure "config requires explicit argument token" run_state config set free-text
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
expect_success "require post-implementation checkpoint" run_state checkpoint require
expect_success "record verification" run_state phase verified
expect_failure "pending checkpoint blocks assessment" run_state phase assessed assessment-confirmed
expect_success "record first correct quiz choice" run_state checkpoint record correct
expect_failure "one correct choice cannot pass checkpoint" run_state checkpoint pass quiz-confirmed
expect_success "switch pending checkpoint to free text" run_state config set free-text argument-confirmed
switched="$(run_state show)"
assert_json "mode switch resets partial quiz without clearing checkpoint" 'value.responseMode === "free-text" && value.checkpointRequired && value.quizQuestionsAnswered === 0 && value.quizCorrectAnswers === 0' "$switched"
expect_failure "quiz result is rejected in free-text mode" run_state checkpoint record correct
expect_success "switch checkpoint back to quiz" run_state config set quiz argument-confirmed
expect_success "restart adaptive checkpoint" run_state checkpoint require
restarted="$(run_state show)"
assert_json "checkpoint restart clears answers" 'value.checkpointRequired === true && value.quizQuestionsAnswered === 0 && value.quizCorrectAnswers === 0' "$restarted"
expect_success "record first correct quiz choice after restart" run_state checkpoint record correct
expect_success "record second correct quiz choice" run_state checkpoint record correct
expect_success "record adaptive quiz result" run_state checkpoint pass quiz-confirmed
expect_failure "assessment requires quiz confirmation" run_state phase assessed
expect_success "record quiz assessment" run_state phase assessed assessment-confirmed

complete="$(run_state show)"
assert_json "task reaches assessed" 'value.schema === 4 && value.phase === "assessed" && value.assessmentMode === "quiz" && typeof value.assessmentConfirmedAt === "string"' "$complete"
expect_failure "completed scope cannot change" run_state scope agent:src/late.js

state_path="$(git -C "$PROJECT" rev-parse --absolute-git-dir)/ducktutor/state.json"
if STATE_PATH="$state_path" JSON_PAYLOAD="$complete" node -e '
  const fs = require("fs");
  const value = JSON.parse(process.env.JSON_PAYLOAD);
  value.schema = 1;
  value.phase = "explained";
  value.explanationConfirmedAt = value.assessmentConfirmedAt;
  delete value.assessmentConfirmedAt;
  delete value.assessmentMode;
  delete value.responseMode;
  fs.writeFileSync(process.env.STATE_PATH, JSON.stringify(value));
'; then
  printf 'PASS state: wrote legacy fixture\n'
else
  printf 'FAIL state: wrote legacy fixture\n'
  FAILURES=$((FAILURES + 1))
fi
legacy="$(run_state show)"
assert_json "legacy explained state migrates to free-text assessment" 'value.schema === 4 && value.phase === "assessed" && value.responseMode === "quiz" && !value.deepReflectionRequired && value.assessmentMode === "free-text" && typeof value.assessmentConfirmedAt === "string" && !("explanationConfirmedAt" in value)' "$legacy"

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
assert_json "cleared project is idle with config preserved" 'value.phase === "idle" && value.responseMode === "quiz"' "$cleared"

expect_success "select free-text mode" run_state config set free-text argument-confirmed
expect_success "begin free-text task" run_state begin "explain checkout decision"
expect_success "predict free-text task" run_state phase predicted
expect_success "scope free-text task" run_state scope learner:src/reflection.js
expect_success "attempt free-text task" run_state phase attempted
expect_success "require free-text checkpoint" run_state checkpoint require
expect_success "verify free-text task" run_state phase verified
expect_failure "quiz pass token is rejected in free-text mode" run_state checkpoint pass quiz-confirmed
expect_success "confirmed free-text response clears checkpoint" run_state checkpoint pass free-text-confirmed
expect_success "assess free-text task" run_state phase assessed assessment-confirmed
free_text_complete="$(run_state show)"
assert_json "free-text assessment mode is recorded" 'value.responseMode === "free-text" && value.assessmentMode === "free-text"' "$free_text_complete"
expect_success "clear free-text task" run_state clear
free_text_idle="$(run_state show)"
assert_json "clear preserves free-text preference" 'value.phase === "idle" && value.responseMode === "free-text"' "$free_text_idle"

expect_success "restore quiz preference" run_state config set quiz argument-confirmed
expect_success "begin next task" run_state begin "scope is required"
expect_success "predict next task" run_state phase predicted
expect_failure "attempt requires ownership map" run_state phase attempted
expect_success "set initial learner scope" run_state scope learner:src/scoped.js
expect_success "expand approved scope" run_state scope learner:src/scoped.js agent:test/scoped.test.js
expanded="$(run_state show)"
assert_json "scope growth requires deep reflection" 'value.deepReflectionRequired === true' "$expanded"
expect_success "require scope-growth checkpoint" run_state checkpoint require
expect_success "temporarily select free text during escalation" run_state config set free-text argument-confirmed
expect_success "reselect quiz during escalation" run_state config set quiz argument-confirmed
still_escalated="$(run_state show)"
assert_json "config cannot downgrade risk escalation" 'value.responseMode === "quiz" && value.deepReflectionRequired === true && value.checkpointRequired' "$still_escalated"
expect_failure "quiz cannot satisfy scope-growth reflection" run_state checkpoint record correct
expect_success "deep reflection satisfies scope-growth checkpoint" run_state checkpoint pass free-text-confirmed
expect_success "clear next task" run_state clear

expect_success "record prior guide command" run_state engage explain
expect_success "enter forced implementation" run_state engage implement --force-agent
expect_success "begin forced task" run_state begin "agent implements approved scope"
expect_success "predict forced task" run_state phase predicted
expect_success "force mode accepts all-agent scope" run_state scope agent:src/forced.js agent:test/forced.test.js
forced="$(run_state show)"
assert_json "force mode requires deep reflection" 'value.implementationMode === "force-agent" && value.deepReflectionRequired === true && value.learnerPaths.length === 0 && value.agentPaths.length === 2' "$forced"
expect_success "require forced checkpoint" run_state checkpoint require
expect_failure "quiz cannot satisfy forced reflection" run_state checkpoint pass quiz-confirmed
expect_success "free-text confirmation satisfies forced reflection" run_state checkpoint pass free-text-confirmed
expect_failure "clean requires explicit argument token" run_state clean
expect_success "clean resets forced task" run_state clean argument-confirmed
cleaned="$(run_state show)"
assert_json "clean removes all state and restores quiz default" 'value.phase === "idle" && value.responseMode === "quiz" && value.engagedCommands.length === 0 && value.unexplainedAgentChanges.length === 0' "$cleaned"

if (( FAILURES > 0 )); then
  printf '%s learning-state test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All learning-state tests passed\n'
