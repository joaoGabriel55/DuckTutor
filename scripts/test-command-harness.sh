#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$ROOT/scripts/command-harness.sh"
STATE="$ROOT/scripts/learning-state.sh"
POST_EDIT="$ROOT/hooks/post-edit.sh"
PROMPT_GATE="$ROOT/hooks/prompt-gate.sh"
SESSION_HOOK="$ROOT/hooks/session-start.sh"
PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/ducktutor-harness.XXXXXX")"
FAILURES=0

cleanup() {
  rm -rf "$PROJECT"
}
trap cleanup EXIT

git -C "$PROJECT" init -q
git -C "$PROJECT" config user.name DuckTutor-Test
git -C "$PROJECT" config user.email test@ducktutor.invalid
git -C "$PROJECT" commit --allow-empty -qm initial

run_harness() {
  DUCKTUTOR_PROJECT_DIR="$PROJECT" "$HARNESS" "$@"
}

expect_success() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then printf 'PASS harness: %s\n' "$name"; else
    printf 'FAIL harness: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_failure() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'FAIL harness rejected: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  else printf 'PASS harness rejected: %s\n' "$name"; fi
}

expect_failure "implement requires a prior DuckTutor command" run_harness enter implement
expect_failure "force-agent requires a prior DuckTutor command" run_harness enter implement --force-agent
expect_success "start command records engagement and creates a new task boundary" run_harness enter start --new-task
expect_success "prior command unlocks implement" run_harness enter implement
expect_success "prior command unlocks force-agent implement" run_harness enter implement --force-agent
expect_failure "unknown implement flag is rejected" run_harness enter implement --force
expect_failure "explain cannot claim a new task boundary" run_harness enter explain --new-task

DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" begin "harness task" >/dev/null
DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" phase predicted >/dev/null
DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" scope agent:src/app.js agent:test/app.test.js >/dev/null

state_after_begin="$(run_harness show)"
if STATE_JSON="$state_after_begin" node -e '
  const state = JSON.parse(process.env.STATE_JSON);
  if (!state.engagedCommands.includes("start") || !state.engagedCommands.includes("implement")) process.exit(1);
  if (state.activeCommand !== "implement") process.exit(1);
  if (state.implementationMode !== "force-agent" || state.learnerPaths.length !== 0) process.exit(1);
'; then printf 'PASS harness: task begin preserves command engagement\n'; else
  printf 'FAIL harness: task begin preserves command engagement\n'
  FAILURES=$((FAILURES + 1))
fi

failed_post_output="$(printf '{"cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Edit","tool_response":{"isError":true}}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$POST_EDIT" 2>/dev/null || true)"
state_after_failed_edit="$(run_harness show)"
if STATE_JSON="$state_after_failed_edit" node -e 'const state = JSON.parse(process.env.STATE_JSON); process.exit(state.checkpointRequired ? 1 : 0)' && [[ -z "$failed_post_output" ]]; then
  printf 'PASS harness: failed edit does not require a checkpoint\n'
else
  printf 'FAIL harness: failed edit does not require a checkpoint\n'
  FAILURES=$((FAILURES + 1))
fi

post_output="$(printf '{"cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Edit","tool_response":{"ok":true}}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$POST_EDIT" 2>/dev/null || true)"
checkpoint_state="$(run_harness show)"
if STATE_JSON="$checkpoint_state" POST_JSON="$post_output" node -e '
  const state = JSON.parse(process.env.STATE_JSON);
  const hook = JSON.parse(process.env.POST_JSON);
  if (!state.checkpointRequired) process.exit(1);
  if (!hook.hookSpecificOutput.additionalContext.includes("comprehension checkpoint")) process.exit(1);
'; then printf 'PASS harness: successful edit requires a checkpoint\n'; else
  printf 'FAIL harness: successful edit requires a checkpoint\n'
  FAILURES=$((FAILURES + 1))
fi

blocked_prompt="$(printf '{"cwd":"%s","prompt":"/ducktutor:review"}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$PROMPT_GATE" 2>/dev/null || true)"
if [[ "$blocked_prompt" == *'"decision":"block"'* && "$blocked_prompt" == *'persists across sessions'* && "$blocked_prompt" == *'/ducktutor:checkpoint --abandon'* ]]; then
  printf 'PASS harness: unanswered checkpoint blocks with cross-session recovery choices\n'
else
  printf 'FAIL harness: unanswered checkpoint blocks with cross-session recovery choices\n'
  FAILURES=$((FAILURES + 1))
fi

checkpoint_prompt="$(printf '{"cwd":"%s","prompt":"/ducktutor:checkpoint"}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$PROMPT_GATE" 2>/dev/null || true)"
if [[ -z "$checkpoint_prompt" ]]; then printf 'PASS harness: checkpoint command remains available\n'; else
  printf 'FAIL harness: checkpoint command remains available\n'
  FAILURES=$((FAILURES + 1))
fi

abandon_prompt="$(printf '{"cwd":"%s","prompt":"/ducktutor:checkpoint --abandon"}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$PROMPT_GATE" 2>/dev/null || true)"
if [[ -z "$abandon_prompt" ]]; then printf 'PASS harness: explicit checkpoint abandonment remains available\n'; else
  printf 'FAIL harness: explicit checkpoint abandonment remains available\n'
  FAILURES=$((FAILURES + 1))
fi

session_output="$(printf '{"source":"startup","cwd":"%s","hook_event_name":"SessionStart"}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$SESSION_HOOK" 2>/dev/null || true)"
if [[ "$session_output" == *'persists across sessions'* && "$session_output" == *'/ducktutor:checkpoint --abandon'* ]]; then
  printf 'PASS harness: new session explains pending-checkpoint recovery\n'
else
  printf 'FAIL harness: new session explains pending-checkpoint recovery\n'
  FAILURES=$((FAILURES + 1))
fi

codex_prompt="$(printf '{"cwd":"%s","prompt":"$ducktutor:tutor Review my changes"}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$PROMPT_GATE" 2>/dev/null || true)"
if [[ "$codex_prompt" == *'"decision":"block"'* ]]; then
  printf 'PASS harness: unanswered checkpoint blocks Codex tutor re-entry\n'
else
  printf 'FAIL harness: unanswered checkpoint blocks Codex tutor re-entry\n'
  FAILURES=$((FAILURES + 1))
fi

embedded_slash_prompt="$(printf '{"cwd":"%s","prompt":"Please run /ducktutor:review now"}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$PROMPT_GATE" 2>/dev/null || true)"
embedded_skill_prompt="$(printf '{"cwd":"%s","prompt":"Please use $ducktutor:tutor to review my changes"}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$PROMPT_GATE" 2>/dev/null || true)"
if [[ "$embedded_slash_prompt" == *'"decision":"block"'* && "$embedded_skill_prompt" == *'"decision":"block"'* ]]; then
  printf 'PASS harness: embedded DuckTutor invocations cannot bypass checkpoint lock\n'
else
  printf 'FAIL harness: embedded DuckTutor invocations cannot bypass checkpoint lock\n'
  FAILURES=$((FAILURES + 1))
fi

expect_failure "entry gate blocks review while unanswered" run_harness enter review
expect_failure "new task cannot bypass unanswered checkpoint" run_harness enter start --new-task
expect_success "entry gate allows checkpoint" run_harness enter checkpoint
expect_failure "checkpoint cannot clear without confirmation" run_harness checkpoint-pass
expect_failure "pending checkpoint cannot be erased" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" clear
expect_success "confirmed understanding clears checkpoint" run_harness checkpoint-pass developer-confirmed
expect_success "commands resume after checkpoint" run_harness enter review
expect_success "record completed attempt" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" phase attempted
expect_success "record completed verification" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" phase verified
expect_success "record completed explanation" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" phase explained developer-confirmed
expect_failure "new-task flag is start-only" run_harness enter review --new-task
expect_success "new start retires completed task" run_harness enter start --new-task

new_task_state="$(run_harness show)"
if STATE_JSON="$new_task_state" PROJECT_ROOT="$PROJECT" node -e '
  const state = JSON.parse(process.env.STATE_JSON);
  if (state.phase !== "idle" || state.task !== "") process.exit(1);
  if (state.learnerPaths.length || state.agentPaths.length || state.checkpointRequired) process.exit(1);
  if (state.activeCommand !== "start" || state.implementationMode !== "hybrid") process.exit(1);
  if (!state.engagedCommands.includes("start") || !state.engagedCommands.includes("implement")) process.exit(1);
  if (state.repositoryRoot !== require("fs").realpathSync(process.env.PROJECT_ROOT) || !state.baselineHead) process.exit(1);
'; then
  printf 'PASS harness: new start preserves engagement but clears unrelated task state\n'
else
  printf 'FAIL harness: new start preserves engagement but clears unrelated task state\n'
  FAILURES=$((FAILURES + 1))
fi

DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" begin "task to abandon" >/dev/null
DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" phase predicted >/dev/null
DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" scope learner:src/old.js agent:test/old.test.js >/dev/null
expect_success "enter implementation before abandoned checkpoint" run_harness enter implement
expect_success "require checkpoint before abandonment" run_harness checkpoint-require
expect_success "enter checkpoint abandonment flow" run_harness enter checkpoint
expect_failure "checkpoint abandonment requires confirmation" run_harness checkpoint-abandon
expect_success "confirmed abandonment unlocks task state" run_harness checkpoint-abandon developer-confirmed

abandoned_state="$(run_harness show)"
if STATE_JSON="$abandoned_state" node -e '
  const state = JSON.parse(process.env.STATE_JSON);
  if (state.phase !== "idle" || state.task !== "" || state.checkpointRequired) process.exit(1);
  if (state.learnerPaths.length || state.agentPaths.length || state.explanationConfirmedAt) process.exit(1);
  if (state.lastAbandonedTask !== "task to abandon" || !state.lastAbandonedAt) process.exit(1);
  if (!state.engagedCommands.includes("implement") || state.activeCommand !== "checkpoint") process.exit(1);
'; then
  printf 'PASS harness: abandonment is recorded without claiming understanding\n'
else
  printf 'FAIL harness: abandonment is recorded without claiming understanding\n'
  FAILURES=$((FAILURES + 1))
fi
expect_success "commands resume after explicit abandonment" run_harness enter review

if (( FAILURES > 0 )); then
  printf '%s command-harness test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All command-harness tests passed\n'
