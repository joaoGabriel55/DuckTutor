#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLEAN="$ROOT/scripts/clean.sh"
HOOK="$ROOT/hooks/clean-command.sh"
SESSION_START="$ROOT/hooks/session-start.sh"
PROMPT_GATE="$ROOT/hooks/prompt-gate.sh"
STATE="$ROOT/scripts/learning-state.sh"
PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/ducktutor-clean.XXXXXX")"
FAILURES=0

cleanup() { rm -rf "$PROJECT"; }
trap cleanup EXIT

git -C "$PROJECT" init -q
git -C "$PROJECT" config user.name DuckTutor-Test
git -C "$PROJECT" config user.email test@ducktutor.invalid
git -C "$PROJECT" commit --allow-empty -q -m initial

run_state() { DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" "$@"; }

expect_output() {
  local name="$1" pattern="$2"
  shift 2
  local output
  if output="$("$@" 2>&1)" && [[ "$output" == *"$pattern"* ]]; then
    printf 'PASS clean: %s\n' "$name"
  else
    printf 'FAIL clean: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_output "help describes full reset" "active tasks, checkpoints, history, and configuration" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$CLEAN" --help

run_state config set free-text argument-confirmed >/dev/null
run_state engage explain >/dev/null
run_state engage implement --force-agent >/dev/null
run_state begin "pending task" >/dev/null
run_state phase predicted >/dev/null
run_state scope agent:src/example.js >/dev/null
run_state phase attempted >/dev/null
run_state checkpoint require >/dev/null

gate_output="$(printf '{"cwd":"%s","prompt":"/ducktutor:clean"}' "$PROJECT" | DUCKTUTOR_PROJECT_DIR="$PROJECT" "$PROMPT_GATE" 2>/dev/null || true)"
if [[ -z "$gate_output" ]]; then
  printf 'PASS clean: pending checkpoint allows recovery command\n'
else
  printf 'FAIL clean: pending checkpoint allows recovery command\n'
  FAILURES=$((FAILURES + 1))
fi

compact_output="$(printf '{"cwd":"%s","source":"compact","hook_event_name":"SessionStart"}' "$PROJECT" | "$SESSION_START")"
compact_state="$(run_state show)"
if STATE_JSON="$compact_state" node -e 'process.exit(JSON.parse(process.env.STATE_JSON).checkpointRequired ? 0 : 1)' &&
   [[ "$compact_output" == *"pending"* ]]; then
  printf 'PASS clean: compaction preserves a pending checkpoint\n'
else
  printf 'FAIL clean: compaction preserves a pending checkpoint\n'
  FAILURES=$((FAILURES + 1))
fi

clear_output="$(printf '{"cwd":"%s","source":"clear","hook_event_name":"SessionStart"}' "$PROJECT" | "$SESSION_START")"
cleared_by_host="$(run_state show)"
lessons_after_clear="$(run_state lessons)"
if STATE_JSON="$cleared_by_host" LESSONS_JSON="$lessons_after_clear" node -e '
  const state = JSON.parse(process.env.STATE_JSON);
  const lessons = JSON.parse(process.env.LESSONS_JSON);
  process.exit(state.phase === "idle" && !state.checkpointRequired &&
    state.lastAbandonedTask === "pending task" &&
    lessons.recent.some((entry) => entry.type === "checkpoint-abandoned" && entry.task === "pending task" && entry.trigger === "host-clear") ? 0 : 1);
' && [[ "$clear_output" == *"automatically abandoned the pending task"* ]]; then
  printf 'PASS clean: host clear abandons and records a pending checkpoint\n'
else
  printf 'FAIL clean: host clear abandons and records a pending checkpoint\n'
  FAILURES=$((FAILURES + 1))
fi

run_state begin "plugin clean task" >/dev/null
run_state phase predicted >/dev/null
run_state scope learner:src/example.js >/dev/null
run_state phase attempted >/dev/null
run_state checkpoint require >/dev/null

hook_output="$(printf '{"cwd":"%s","command_name":"ducktutor:clean","command_args":"","hook_event_name":"UserPromptExpansion"}' "$PROJECT" | "$HOOK")"
if HOOK_JSON="$hook_output" node -e '
  const value = JSON.parse(process.env.HOOK_JSON);
  process.exit(value.decision === "block" && value.reason.includes("state cleaned") ? 0 : 1);
'; then
  printf 'PASS clean: hook resets state before model expansion\n'
else
  printf 'FAIL clean: hook resets state before model expansion\n'
  FAILURES=$((FAILURES + 1))
fi

state_path="$(git -C "$PROJECT" rev-parse --absolute-git-dir)/ducktutor/state.json"
if [[ ! -e "$state_path" ]]; then
  printf 'PASS clean: persisted state is removed\n'
else
  printf 'FAIL clean: persisted state is removed\n'
  FAILURES=$((FAILURES + 1))
fi

cleaned="$(run_state show)"
if STATE_JSON="$cleaned" node -e '
  const state = JSON.parse(process.env.STATE_JSON);
  process.exit(state.phase === "idle" && state.responseMode === "quiz" &&
    !state.checkpointRequired && state.unexplainedAgentChanges.length === 0 ? 0 : 1);
'; then
  printf 'PASS clean: fresh state defaults to quiz\n'
else
  printf 'FAIL clean: fresh state defaults to quiz\n'
  FAILURES=$((FAILURES + 1))
fi

mkdir -p "$(dirname "$state_path")"
printf '{invalid' > "$state_path"
expect_output "recovers from malformed persisted state" "state cleaned" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$CLEAN"
if [[ ! -e "$state_path" ]]; then
  printf 'PASS clean: malformed state is removed\n'
else
  printf 'FAIL clean: malformed state is removed\n'
  FAILURES=$((FAILURES + 1))
fi

if DUCKTUTOR_PROJECT_DIR="$PROJECT" "$CLEAN" --force >/dev/null 2>&1; then
  printf 'FAIL clean: rejects unknown arguments\n'
  FAILURES=$((FAILURES + 1))
else
  printf 'PASS clean: rejects unknown arguments\n'
fi

if (( FAILURES > 0 )); then
  printf '%s clean-command test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All clean-command tests passed\n'
