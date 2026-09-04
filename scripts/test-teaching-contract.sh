#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

expect_text() {
  local name="$1"
  local pattern="$2"
  shift 2
  if grep -Eiq -- "$pattern" "$@"; then
    printf 'PASS teaching contract: %s\n' "$name"
  else
    printf 'FAIL teaching contract: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

for file in "$ROOT"/commands/*.md; do
  if [[ "$(basename "$file")" == "config.md" || "$(basename "$file")" == "clean.md" ]]; then
    expect_text "$(basename "$file") disables model invocation" 'disable-model-invocation: true' "$file"
    continue
  fi
  expect_text "$(basename "$file") can access learning state" 'learning-state\.sh' "$file"
  expect_text "$(basename "$file") enters canonical deterministic harness" '\$\{CLAUDE_PLUGIN_ROOT\}/scripts/command-harness\.sh"? enter' "$file"
done

expect_text "start creates an explicit new task" 'command-harness\.sh"? enter start --new-task' "$ROOT/commands/start.md"
expect_text "explain remains understanding-only" 'Do not begin task state' "$ROOT/commands/explain.md"
expect_text "start offers a direct hybrid handoff" '/ducktutor:implement`' "$ROOT/commands/start.md"
expect_text "start offers an explicit all-agent handoff" '/ducktutor:implement --force-agent' "$ROOT/commands/start.md"
expect_text "implement can reuse the prepared task" 'Use the prepared task' "$ROOT/commands/implement.md"
expect_text "review surfaces unexplained retired changes" 'unexplainedAgentChanges' "$ROOT/commands/review.md"

if grep -ERq '`(command-harness|learning-state)\.sh' "$ROOT/commands"; then
  printf 'FAIL teaching contract: command prompts contain a bare internal script invocation\n'
  FAILURES=$((FAILURES + 1))
else
  printf 'PASS teaching contract: command prompts use only canonical internal script paths\n'
fi

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

expect_text "zero-model config expansion hook configured" 'UserPromptExpansion' "$ROOT/hooks/hooks.json"
expect_text "config expansion targets deterministic hook" 'config-command\.sh' "$ROOT/hooks/hooks.json"
expect_text "clean expansion targets deterministic hook" 'clean-command\.sh' "$ROOT/hooks/hooks.json"

if HOOKS_FILE="$ROOT/hooks/hooks.json" node -e '
  const hooks = JSON.parse(require("fs").readFileSync(process.env.HOOKS_FILE, "utf8")).hooks;
  const globalEnforcement = ["SessionStart", "PreToolUse", "PostToolUse", "UserPromptSubmit"];
  process.exit(globalEnforcement.some((event) => event in hooks) ? 1 : 0);
'; then
  printf 'PASS teaching contract: enforcement is inactive outside explicit DuckTutor commands\n'
else
  printf 'FAIL teaching contract: enforcement is inactive outside explicit DuckTutor commands\n'
  FAILURES=$((FAILURES + 1))
fi

for file in "$ROOT"/commands/{teach-me,start,explain,review,hint,checkpoint,implement}.md; do
  expect_text "$(basename "$file") scopes the mutation guard" 'guard\.sh tool' "$file"
  expect_text "$(basename "$file") scopes post-edit checkpoints" 'post-edit\.sh' "$file"
done

expect_text "Codex tutor requires explicit invocation" 'allow_implicit_invocation: false' "$ROOT/skills/tutor/agents/openai.yaml"
expect_text "implement exposes explicit force-agent mode" '--force-agent' "$ROOT/commands/implement.md" "$ROOT/skills/tutor/SKILL.md"
expect_text "checkpoint exposes explicit abandonment" '--abandon' "$ROOT/commands/checkpoint.md" "$ROOT/skills/tutor/SKILL.md"
expect_text "config exposes direct mode flags" '--mode=<mode>' "$ROOT/skills/tutor/SKILL.md"
expect_text "shared tutor caps routine output" 'within 120 words' "$ROOT/skills/tutor/SKILL.md"
expect_text "shared tutor caps simple verdicts" 'simple verdicts within 80' "$ROOT/skills/tutor/SKILL.md"
expect_text "shared tutor avoids prompt restatement" 'Do not restate supplied facts' "$ROOT/skills/tutor/SKILL.md"
expect_text "shared tutor blocks MCP file mutation absolutely" 'MCP file mutation is always blocked' "$ROOT/skills/tutor/SKILL.md"
expect_text "shared tutor requires approval for unknown capabilities" 'unknown capabilities require approval' "$ROOT/skills/tutor/SKILL.md"
expect_text "shared tutor reports observed evidence" 'Report expected versus observed behavior' "$ROOT/skills/tutor/SKILL.md"
expect_text "shared tutor defaults response mode to quiz" 'quiz.*default' "$ROOT/skills/tutor/SKILL.md"
expect_text "shared tutor supports exact-set multi-select checkpoints" 'exact answer set|omissions or extra selections' "$ROOT/skills/tutor/SKILL.md" "$ROOT/commands/checkpoint.md"
expect_text "live evaluator enforces routine output cap" 'wordCount.*<= 120' "$ROOT/scripts/eval-teaching.mjs"

if node -e '
  const fs = require("fs");
  const root = process.argv[1];
  const versions = [
    JSON.parse(fs.readFileSync(`${root}/.codex-plugin/plugin.json`)).version,
    JSON.parse(fs.readFileSync(`${root}/.claude-plugin/plugin.json`)).version,
    JSON.parse(fs.readFileSync(`${root}/.claude-plugin/marketplace.json`)).plugins[0].version,
  ];
  if (!versions.every(version => version === versions[0]) || !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(versions[0])) process.exit(1);
' "$ROOT"; then
  printf 'PASS teaching contract: plugin manifests share a stable release version\n'
else
  printf 'FAIL teaching contract: plugin manifests share a stable release version\n'
  FAILURES=$((FAILURES + 1))
fi

if node -e '
  const cases = require(process.argv[1]);
  const ids = new Set(cases.map(entry => entry.id));
  const checks = new Set(cases.flatMap(entry => entry.checks));
  if (!ids.has("learner-owned-refusal") || !ids.has("adaptive-checkpoint-required") ||
      !ids.has("progressive-hint-after-failed-nudge") || !checks.has("no_code") ||
      !ids.has("quiz-answer-position") || !ids.has("post-implementation-checkpoint") || !ids.has("configured-free-text-checkpoint") ||
      !ids.has("unexplained-retired-changes") || !ids.has("resolved-retired-changes") || !ids.has("disproportionate-diff") ||
      !ids.has("speculative-abstraction") || !ids.has("constraint-earned-abstraction") || !ids.has("local-pass-hidden-coupling") ||
      !ids.has("risk-escalated-checkpoint") ||
      !checks.has("choice_question") || !checks.has("multi_select") || !checks.has("unsure_option") || !checks.has("no_free_text") || !checks.has("free_text_checkpoint") || !checks.has("phase_fit") ||
      !checks.has("unexplained_changes") || !checks.has("no_false_unexplained") || !checks.has("proportionality") ||
      !checks.has("earned_abstraction") || !checks.has("justified_abstraction") || !checks.has("system_reasoning") ||
      !checks.has("deep_reflection") || !checks.has("risk_escalation") || !checks.has("reject_restart") ||
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
