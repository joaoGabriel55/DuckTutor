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

node -e '
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: "DuckTutor recorded a required comprehension checkpoint after this edit. Finish the scoped implementation, inspect the real diff, then ask one open-ended quiz about a load-bearing decision and failure mode. Do not clear the checkpoint until the developer answers satisfactorily.",
    },
  }) + "\n");
'
