#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD="$(cat 2>/dev/null || true)"

if [[ -z "${DUCKTUTOR_PROJECT_DIR:-}" ]]; then
  DUCKTUTOR_PROJECT_DIR="$(PAYLOAD_JSON="$PAYLOAD" node -e '
    try {
      const payload = JSON.parse(process.env.PAYLOAD_JSON || "{}");
      process.stdout.write(typeof payload.cwd === "string" ? payload.cwd : process.cwd());
    } catch (_) { process.stdout.write(process.cwd()); }
  ')"
fi

if ! PAYLOAD_JSON="$PAYLOAD" node -e '
  try {
    const response = JSON.parse(process.env.PAYLOAD_JSON || "{}").tool_response;
    if (response?.isError === true || response?.success === false || response?.error) process.exit(1);
  } catch (_) { process.exit(1); }
'; then
  exit 0
fi

if ! DUCKTUTOR_PROJECT_DIR="$DUCKTUTOR_PROJECT_DIR" "$ROOT/scripts/command-harness.sh" checkpoint-require >/dev/null 2>&1; then
  exit 0
fi

STATE_JSON="$(DUCKTUTOR_PROJECT_DIR="$DUCKTUTOR_PROJECT_DIR" "$ROOT/scripts/command-harness.sh" show 2>/dev/null || true)"
STATE_JSON="$STATE_JSON" node -e '
  const state = JSON.parse(process.env.STATE_JSON || "{}");
  const mode = state.deepReflectionRequired ? "deep-reflection" : (state.responseMode || "quiz");
  const guidance = mode !== "quiz"
    ? "ask for one explanation of a load-bearing decision and failure mode"
    : "ask the adaptive choice quiz, using multi-select when several answers are correct, and pass only after two correct questions within three";
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: `DuckTutor recorded a required ${mode} checkpoint after this edit. Finish the scoped implementation, inspect the real diff, then ${guidance}. The response is evidence, not proof of understanding.`,
    },
  }) + "\n");
'
