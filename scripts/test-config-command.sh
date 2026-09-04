#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/scripts/config.sh"
HOOK="$ROOT/hooks/config-command.sh"
STATE="$ROOT/scripts/learning-state.sh"
PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/ducktutor-config.XXXXXX")"
FAILURES=0

cleanup() { rm -rf "$PROJECT"; }
trap cleanup EXIT

git -C "$PROJECT" init -q
git -C "$PROJECT" config user.name DuckTutor-Test
git -C "$PROJECT" config user.email test@ducktutor.invalid
git -C "$PROJECT" commit --allow-empty -q -m initial

expect_output() {
  local name="$1" pattern="$2"
  shift 2
  local output
  if output="$("$@" 2>&1)" && [[ "$output" == *"$pattern"* ]]; then
    printf 'PASS config: %s\n' "$name"
  else
    printf 'FAIL config: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_output "help describes quiz mode" "quiz       Default" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$CONFIG" --help
expect_output "help describes free-text mode" "free-text  Ask concise" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$CONFIG" --help
expect_output "help describes risk override" "require deep reflection even in quiz mode" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$CONFIG" --help
expect_output "sets free-text directly" "response mode set to free-text" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$CONFIG" --mode=free-text

state="$(DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" show)"
if STATE_JSON="$state" node -e 'const state = JSON.parse(process.env.STATE_JSON); process.exit(state.responseMode === "free-text" ? 0 : 1)'; then
  printf 'PASS config: persists selected mode\n'
else
  printf 'FAIL config: persists selected mode\n'
  FAILURES=$((FAILURES + 1))
fi

if DUCKTUTOR_PROJECT_DIR="$PROJECT" "$CONFIG" --mode=voice >/dev/null 2>&1; then
  printf 'FAIL config: rejects unknown mode\n'
  FAILURES=$((FAILURES + 1))
else
  printf 'PASS config: rejects unknown mode\n'
fi

hook_output="$(printf '{"cwd":"%s","command_name":"ducktutor:config","command_args":"--mode=quiz","hook_event_name":"UserPromptExpansion"}' "$PROJECT" | "$HOOK")"
if HOOK_JSON="$hook_output" node -e '
  const value = JSON.parse(process.env.HOOK_JSON);
  process.exit(value.decision === "block" && value.reason.includes("response mode set to quiz") ? 0 : 1);
'; then
  printf 'PASS config: hook handles command before model expansion\n'
else
  printf 'FAIL config: hook handles command before model expansion\n'
  FAILURES=$((FAILURES + 1))
fi

help_output="$(printf '{"cwd":"%s","command_name":"ducktutor:config","command_args":"--help","hook_event_name":"UserPromptExpansion"}' "$PROJECT" | "$HOOK")"
if HOOK_JSON="$help_output" node -e 'const value = JSON.parse(process.env.HOOK_JSON); process.exit(value.decision === "block" && value.reason.includes("--mode=quiz") && value.reason.includes("--mode=free-text") ? 0 : 1)'; then
  printf 'PASS config: hook returns deterministic help\n'
else
  printf 'FAIL config: hook returns deterministic help\n'
  FAILURES=$((FAILURES + 1))
fi

if (( FAILURES > 0 )); then
  printf '%s config-command test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All config-command tests passed\n'
