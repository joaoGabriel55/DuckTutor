#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD="$(cat 2>/dev/null || true)"

readarray_output="$(PAYLOAD_JSON="$PAYLOAD" node -e '
  try {
    const payload = JSON.parse(process.env.PAYLOAD_JSON || "{}");
    process.stdout.write(`${typeof payload.cwd === "string" ? payload.cwd : process.cwd()}\n${typeof payload.prompt === "string" ? payload.prompt : ""}`);
  } catch (_) { process.exit(1); }
' 2>/dev/null || true)"
CWD_VALUE="${readarray_output%%$'\n'*}"
PROMPT="${readarray_output#*$'\n'}"
[[ -n "$CWD_VALUE" ]] || exit 0

STATE_JSON="$(DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$CWD_VALUE}" "$ROOT/scripts/command-harness.sh" show 2>/dev/null || true)"
[[ -n "$STATE_JSON" ]] || exit 0

if ! STATE_JSON="$STATE_JSON" node -e 'const state = JSON.parse(process.env.STATE_JSON); process.exit(state.checkpointRequired ? 0 : 1)'; then
  exit 0
fi

COMMAND="$(PROMPT_VALUE="$PROMPT" node -e '
  const prompt = process.env.PROMPT_VALUE || "";
  const slash = prompt.match(/(?:^|\s)\/(?:ducktutor:)?(teach-me|start|explain|review|hint|checkpoint|implement)\b/i);
  if (slash) process.stdout.write(slash[1].toLowerCase());
  else {
    const skill = prompt.match(/\$ducktutor:tutor\b([\s\S]*)/i);
    if (skill) {
      const checkpoint = /^\s*(?:checkpoint|quiz(?: me)?|check (?:my )?understanding)\b/i.test(skill[1]);
      process.stdout.write(checkpoint ? "checkpoint" : "tutor");
    }
  }
')"

[[ -n "$COMMAND" && "$COMMAND" != "checkpoint" ]] || exit 0

STATE_JSON="$STATE_JSON" node -e '
  const state = JSON.parse(process.env.STATE_JSON);
  const task = state.task ? ` for task ${JSON.stringify(state.task)}` : "";
  process.stdout.write(JSON.stringify({
    decision: "block",
    reason: `DuckTutor has a pending comprehension checkpoint${task}. It persists across sessions. Run /ducktutor:checkpoint to answer, or /ducktutor:checkpoint --abandon to explicitly discard the task without claiming understanding.`,
  }) + "\n");
'
