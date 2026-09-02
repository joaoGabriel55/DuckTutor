---
description: Understand an issue, predict the approach, and approve a hybrid file-ownership map without dictating learner-owned code.
argument-hint: "<issue URL or problem description>"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh issue view *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · explain

Use the **tutor** skill in guide-only mode. First run `command-harness.sh enter explain`; stop if it
rejects entry. Require `$ARGUMENTS`, inspect enough context, and begin
persistent learning state. State the behavior, smallest viable change, riskiest edge case, and
verification signal. Ask one prediction question and wait, then record `predicted`.

Propose learner-owned and agent-editable files and wait for approval before persisting the scope.
Explain learner-owned code by goal, constraints, and shape; do not dictate it. Give the next useful
hint and inspect the real attempt before treating it as complete.
