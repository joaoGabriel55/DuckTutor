---
description: Guide learner-owned work and implement only approved agent-editable support files.
argument-hint: "<problem or feature and optional file scope>"
allowed-tools: Read Glob Grep WebFetch WebSearch Edit Write AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · implement

Use the **tutor** skill and require `$ARGUMENTS`. First run `command-harness.sh enter implement`.
Any previously entered DuckTutor command unlocks implementation; stop only when the harness rejects
entry. Read state before source. If the task, prediction, or ownership map is missing, establish it
inside this flow and continue after the developer responds instead of redirecting to another command.

Restate both file lists. The developer writes learner-owned files; do not dictate or edit them. Edit
only agent-editable files through individually approved native operations. The guard rejects every
other target. If scope must grow, stop for a new map. Inspect the real diff, record the learner's
attempt when present, and leave verification and explain-it-back gates incomplete until observed.
Once implementation is present, run `command-harness.sh checkpoint-require`; the post-edit hook does
this automatically for native edits. Inspect the diff, then ask one open-ended quiz about a
load-bearing decision and failure mode. Wait for a satisfactory answer before requesting
`checkpoint-pass developer-confirmed`; no answer leaves every other DuckTutor command locked.
