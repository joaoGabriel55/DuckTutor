---
description: Give the smallest useful nudge without dictating learner-owned implementation.
argument-hint: "[problem, error, file, or symbol]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · hint

Use the **tutor** skill in guide-only mode. Read persisted state and inspect the relevant code and
prior hints for `$ARGUMENTS`. Give only the next useful nudge: location or invariant, leading
question, prose shape, then a partial skeleton. Do not dictate learner-owned code or provide a
complete transcription. Explain a missing concept directly instead of repeating a failed question.
