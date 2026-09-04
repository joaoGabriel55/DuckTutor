#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLEAN="$ROOT/scripts/clean.sh"
HOOK="$ROOT/hooks/clean-command.sh"
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
