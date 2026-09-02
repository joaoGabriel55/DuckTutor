#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

expect_text() {
  local name="$1"
  local pattern="$2"
  shift 2
  if grep -Eiq "$pattern" "$@"; then
    printf 'PASS teaching contract: %s\n' "$name"
  else
    printf 'FAIL teaching contract: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

for file in "$ROOT"/commands/*.md; do
  expect_text "$(basename "$file") can access learning state" 'learning-state\.sh' "$file"
  expect_text "$(basename "$file") enters deterministic harness" 'command-harness\.sh.*enter' "$file"
done

for file in "$ROOT"/commands/*.md; do
  if [[ "$(basename "$file")" == "implement.md" ]]; then
    expect_text "implement exposes native edits" 'allowed-tools:.*Edit.*Write' "$file"
  elif grep -Eq '^allowed-tools:.*(Edit|Write)' "$file"; then
    printf 'FAIL teaching contract: %s unexpectedly exposes native edits\n' "$(basename "$file")"
    FAILURES=$((FAILURES + 1))
  else
    printf 'PASS teaching contract: %s remains guide-only\n' "$(basename "$file")"
  fi
done

expect_text "session-start hook configured" 'SessionStart' "$ROOT/hooks/hooks.json"
expect_text "post-edit checkpoint hook configured" 'PostToolUse' "$ROOT/hooks/hooks.json"
expect_text "pending-checkpoint prompt gate configured" 'UserPromptSubmit' "$ROOT/hooks/hooks.json"

if node -e '
  const cases = require(process.argv[1]);
  const ids = new Set(cases.map(entry => entry.id));
  const checks = new Set(cases.flatMap(entry => entry.checks));
  if (!ids.has("learner-owned-refusal") || !ids.has("explain-it-back-required") ||
      !ids.has("progressive-hint-after-failed-nudge") || !checks.has("no_code") ||
      !ids.has("quiz-answer-position") || !ids.has("post-implementation-checkpoint") ||
      !checks.has("own_words") || !checks.has("phase_fit") ||
      !checks.has("stronger_hint") || !checks.has("quiz_variation") ||
      !checks.has("no_premature_completion")) process.exit(1);
' "$ROOT/evals/teaching-cases.json"; then
  printf 'PASS teaching contract: live eval covers ownership and understanding\n'
else
  printf 'FAIL teaching contract: live eval covers ownership and understanding\n'
  FAILURES=$((FAILURES + 1))
fi

if (( FAILURES > 0 )); then
  printf '%s teaching-contract test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All teaching-contract tests passed\n'
