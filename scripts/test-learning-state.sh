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
assert_json "new project defaults to quiz mode" 'value.phase === "idle" && value.schema === 5 && value.responseMode === "quiz" && !value.deepReflectionRequired' "$initial"
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
assert_json "task reaches assessed" 'value.schema === 5 && value.phase === "assessed" && value.assessmentMode === "quiz" && typeof value.assessmentConfirmedAt === "string"' "$complete"
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
assert_json "legacy explained state migrates to free-text assessment" 'value.schema === 5 && value.phase === "assessed" && value.responseMode === "quiz" && !value.deepReflectionRequired && value.assessmentMode === "free-text" && typeof value.assessmentConfirmedAt === "string" && !("explanationConfirmedAt" in value)' "$legacy"

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

initial_lessons="$(run_state lessons)"
assert_json "fresh project has no lessons" 'value.schema === 1 && value.total === 0 && value.recent.length === 0' "$initial_lessons"

expect_success "begin task for lessons log" run_state begin "lessons log task"
expect_success "predict lessons task" run_state phase predicted
expect_success "scope lessons task" run_state scope learner:src/lesson.js
expect_success "attempt lessons task" run_state phase attempted
expect_success "require lessons checkpoint" run_state checkpoint require
expect_success "record incorrect checkpoint choice" run_state checkpoint record incorrect

after_incorrect="$(run_state lessons)"
assert_json "incorrect answer is mechanically logged" 'value.total === 1 && value.recent[0].type === "checkpoint-incorrect" && value.recent[0].task === "lessons log task" && typeof value.recent[0].ts === "string"' "$after_incorrect"

expect_success "abandon lessons checkpoint" run_state checkpoint abandon choice-confirmed
after_abandon="$(run_state lessons)"
assert_json "abandonment is mechanically logged" 'value.total === 2 && value.recent[1].type === "checkpoint-abandoned" && value.recent[1].task === "lessons log task"' "$after_abandon"

expect_success "clean resets lessons log too" run_state clean argument-confirmed
after_clean="$(run_state lessons)"
assert_json "clean clears the lessons log" 'value.total === 0 && value.recent.length === 0' "$after_clean"

# --- event-driven advancement -------------------------------------------------

assert_json "next asks for a task when idle" 'value.action === "begin-task" && value.phase === "idle" && !value.blocked' "$(run_state next)"

expect_success "begin an event-driven task" run_state begin "event driven task"
assert_json "begin grounds the task" 'value.phase === "grounded"' "$(run_state show)"
assert_json "next asks for an ownership map" 'value.action === "record-scope" && !value.blocked' "$(run_state next)"

expect_failure "scope rejects dual ownership" run_state scope learner:same.js agent:same.js
expect_success "scope from grounded" run_state scope learner:owner.js agent:helper.js
assert_json "recording ownership predicts" 'value.phase === "predicted" && value.learnerPaths.length === 1 && value.agentPaths.length === 1' "$(run_state show)"
assert_json "next asks for the scoped edit" 'value.action === "implement-scoped-edits"' "$(run_state next)"

expect_success "re-scoping is idempotent" run_state scope learner:owner.js agent:helper.js
assert_json "re-scoping does not skip a phase" 'value.phase === "predicted"' "$(run_state show)"

expect_success "requiring a checkpoint records the attempt" run_state checkpoint require
assert_json "checkpoint-require advances to attempted" 'value.phase === "attempted" && value.checkpointRequired' "$(run_state show)"
assert_json "next blocks on the pending checkpoint" 'value.action === "run-checkpoint" && value.blocked' "$(run_state next)"

expect_failure "verify rejects control characters" run_state verify $'ran\ntests'
expect_failure "verify rejects an empty summary" run_state verify ""

expect_success "pass the checkpoint before verifying" run_state checkpoint record correct
expect_success "pass the second choice" run_state checkpoint record correct
expect_success "confirm the quiz" run_state checkpoint pass quiz-confirmed
assert_json "passing alone does not assess" 'value.phase === "attempted" && !value.checkpointRequired' "$(run_state show)"

expect_success "record verification evidence" run_state verify "ran the suite, 42 passing"
assert_json "evidence completes the assessment join" 'value.phase === "assessed" && value.verifiedEvidence === "ran the suite, 42 passing" && typeof value.assessmentConfirmedAt === "string"' "$(run_state show)"

assert_json "next offers completion" 'value.action === "complete-task"' "$(run_state next)"
expect_success "complete the assessed task" run_state complete
completed="$(run_state show)"
assert_json "completion retires the task" 'value.phase === "idle" && value.task === "" && value.lastCompletedTask.task === "event driven task" && value.lastCompletedTask.assessmentMode === "quiz" && value.lastCompletedTask.verifiedEvidence === "ran the suite, 42 passing"' "$completed"
expect_failure "only an assessed task completes" run_state complete

# --- remediation --------------------------------------------------------------

expect_success "begin a task that will fail its checkpoints" run_state begin "remediation task"
expect_success "scope the remediation task" run_state scope learner:owner.js agent:helper.js
expect_success "arm the first checkpoint" run_state checkpoint require
for _ in 1 2 3; do run_state checkpoint record incorrect >/dev/null 2>&1; done
expect_success "arm a second cycle after failing" run_state checkpoint require
assert_json "first failed cycle is counted" 'value.checkpointCycles === 1 && !value.remediationRequired' "$(run_state show)"
for _ in 1 2 3; do run_state checkpoint record incorrect >/dev/null 2>&1; done
expect_success "arm a third cycle after failing again" run_state checkpoint require
remediating="$(run_state show)"
assert_json "two failed cycles force remediation" 'value.checkpointCycles === 2 && value.remediationRequired && value.deepReflectionRequired && value.remediationTopic === "remediation task"' "$remediating"
assert_json "next routes back to teaching" 'value.action === "remediate" && value.blocked' "$(run_state next)"
assert_json "remediation is mechanically logged" 'value.recent.some((entry) => entry.type === "checkpoint-remediation" && entry.cycles === 2)' "$(run_state lessons)"

expect_failure "remediation still blocks review" run_state engage review
expect_success "remediation reopens teaching" run_state engage teach-me
expect_success "remediation reopens explanation" run_state engage explain

if (( FAILURES > 0 )); then
  printf '%s learning-state test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All learning-state tests passed\n'
