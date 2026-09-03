---
description: Check understanding of an applied change or explicitly abandon its pending task.
argument-hint: "[--abandon | optional file, path, or concept]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · checkpoint

Use the **tutor** skill; run `"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" enter checkpoint`.
For exact argument `--abandon`, show the task and time, state that understanding is not
recorded, and confirm. If confirmed, run
`"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" checkpoint-abandon developer-confirmed` and stop.

Otherwise inspect state and diff. Ask for one load-bearing decision and failure mode
in the developer's words; correct misconceptions. A quiz only reinforces. After a satisfactory answer,
run `"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" checkpoint-pass developer-confirmed`, then
`"${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" phase explained developer-confirmed` when applicable.
Never edit.
