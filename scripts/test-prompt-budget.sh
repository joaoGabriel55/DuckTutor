#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/skills/tutor/SKILL.md"
SKILL_LIMIT=450
COMMANDS_LIMIT=700
RUNTIME_LIMIT=900
FAILURES=0

body_words() {
  awk '
    /^---$/ { separators++; next }
    separators >= 2 { words += NF }
    END { print words + 0 }
  ' "$1"
}

skill_words="$(body_words "$SKILL")"
commands_words=0
max_runtime=0

for file in "$ROOT"/commands/*.md; do
  command_words="$(body_words "$file")"
  runtime_words=$((skill_words + command_words))
  commands_words=$((commands_words + command_words))
  if (( runtime_words > max_runtime )); then
    max_runtime=$runtime_words
  fi
done

check_limit() {
  local name="$1"
  local actual="$2"
  local limit="$3"
  if (( actual <= limit )); then
    printf 'PASS prompt budget: %s (%d <= %d words)\n' "$name" "$actual" "$limit"
  else
    printf 'FAIL prompt budget: %s (%d > %d words)\n' "$name" "$actual" "$limit"
    FAILURES=$((FAILURES + 1))
  fi
}

check_limit "shared skill body" "$skill_words" "$SKILL_LIMIT"
check_limit "combined command bodies" "$commands_words" "$COMMANDS_LIMIT"
check_limit "largest skill plus command body" "$max_runtime" "$RUNTIME_LIMIT"

if (( FAILURES > 0 )); then
  exit 1
fi

printf 'All prompt budgets passed\n'
