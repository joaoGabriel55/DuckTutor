#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DISCOVER="$ROOT/scripts/project-context.sh"
SESSION_HOOK="$ROOT/hooks/session-start.sh"
PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/ducktutor-context.XXXXXX")"
FAILURES=0

cleanup() {
  rm -rf "$PROJECT"
}
trap cleanup EXIT

mkdir -p "$PROJECT/apps/web" "$PROJECT/.agents/skills/review" "$PROJECT/.codex/skills/test" \
  "$PROJECT/.claude/skills/ui" "$PROJECT/apps/web/.agents/skills/local" \
  "$PROJECT/.github/workflows" "$PROJECT/node_modules/ignored"
git -C "$PROJECT" init -q

printf 'root instructions\n' > "$PROJECT/AGENTS.md"
printf 'web instructions\n' > "$PROJECT/apps/web/AGENTS.md"
printf 'web override\n' > "$PROJECT/apps/web/AGENTS.override.md"
printf 'claude instructions\n' > "$PROJECT/CLAUDE.md"
printf 'review skill\n' > "$PROJECT/.agents/skills/review/SKILL.md"
printf 'test skill\n' > "$PROJECT/.codex/skills/test/SKILL.md"
printf 'ui skill\n' > "$PROJECT/.claude/skills/ui/SKILL.md"
printf 'local skill\n' > "$PROJECT/apps/web/.agents/skills/local/SKILL.md"
printf '{}\n' > "$PROJECT/.claude/settings.json"
printf '{}\n' > "$PROJECT/.codex/hooks.json"
printf '{}\n' > "$PROJECT/.mcp.json"
printf '{}\n' > "$PROJECT/package.json"
printf '{}\n' > "$PROJECT/apps/web/package.json"
printf 'all:\n' > "$PROJECT/apps/web/Makefile"
printf 'workflow\n' > "$PROJECT/.github/workflows/ci.yml"
printf 'ignore me\n' > "$PROJECT/node_modules/ignored/AGENTS.md"

output="$(DUCKTUTOR_PROJECT_DIR="$PROJECT/apps/web" "$DISCOVER" show 2>/dev/null || true)"

if JSON_PAYLOAD="$output" node -e '
  const value = JSON.parse(process.env.JSON_PAYLOAD);
  const equal = (actual, expected) => JSON.stringify(actual) === JSON.stringify(expected);
  if (value.schema !== 1) process.exit(1);
  if (!equal(value.applicableInstructions, ["AGENTS.md", "CLAUDE.md", "apps/web/AGENTS.override.md"])) process.exit(1);
  if (!value.projectInstructions.includes("apps/web/AGENTS.md") || !value.projectInstructions.includes("apps/web/AGENTS.override.md")) process.exit(1);
  if (value.projectInstructions.some(path => path.includes("node_modules"))) process.exit(1);
  if (!equal(value.skills, [".agents/skills/review/SKILL.md", ".claude/skills/ui/SKILL.md", ".codex/skills/test/SKILL.md", "apps/web/.agents/skills/local/SKILL.md"])) process.exit(1);
  if (!value.automation.includes(".claude/settings.json") || !value.automation.includes(".codex/hooks.json") || !value.automation.includes(".github/workflows/ci.yml") || !value.automation.includes(".mcp.json")) process.exit(1);
  if (!value.references.includes("package.json") || !value.references.includes("apps/web/package.json") || !value.references.includes("apps/web/Makefile")) process.exit(1);
'; then
  printf 'PASS project context: discovers applicable instructions, skills, automation, and references\n'
else
  printf 'FAIL project context: discovers applicable instructions, skills, automation, and references\n'
  FAILURES=$((FAILURES + 1))
fi

session_output="$(printf '{"source":"startup","cwd":"%s","hook_event_name":"SessionStart"}' "$PROJECT/apps/web" | DUCKTUTOR_PROJECT_DIR="$PROJECT/apps/web" "$SESSION_HOOK" 2>/dev/null || true)"
if JSON_PAYLOAD="$session_output" node -e '
  const value = JSON.parse(process.env.JSON_PAYLOAD);
  const context = value.hookSpecificOutput.additionalContext;
  if (!context.includes("Project context inventory")) process.exit(1);
  if (!context.includes("apps/web/AGENTS.override.md") || !context.includes(".agents/skills/review/SKILL.md")) process.exit(1);
  if (!context.includes(".mcp.json") || context.includes("root instructions")) process.exit(1);
'; then
  printf 'PASS project context: session hook restores a path-only project inventory\n'
else
  printf 'FAIL project context: session hook restores a path-only project inventory\n'
  FAILURES=$((FAILURES + 1))
fi

if [[ "$output" != *'root instructions'* && "$output" != *'review skill'* ]]; then
  printf 'PASS project context: inventories paths without copying contents\n'
else
  printf 'FAIL project context: inventories paths without copying contents\n'
  FAILURES=$((FAILURES + 1))
fi

if (( FAILURES > 0 )); then
  printf '%s project-context test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All project-context tests passed\n'
