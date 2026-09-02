---
description: Implement the prepared task in guided hybrid mode or explicitly assign every approved file to the agent.
argument-hint: "[--force-agent] [problem or feature and optional file scope]"
allowed-tools: Read Glob Grep WebFetch WebSearch Edit Write AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · implement

Use the **tutor** skill. If `$ARGUMENTS` contains the exact token `--force-agent`, remove that token
from the task and first run
`"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" enter implement --force-agent`;
otherwise run `"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" enter implement`.
Any previously entered non-implement DuckTutor command unlocks implementation; stop when the harness rejects
entry. Read state before source. Use the prepared task when `$ARGUMENTS` contains no task text, so
`/start …` can hand off directly to `/implement` without repetition. If neither state nor arguments
provide a task, or if the prediction or ownership map is missing, establish it inside this flow and
continue after the developer responds instead of redirecting to another command.

In hybrid mode, the developer writes learner-owned files; do not dictate or edit them. In force-agent
mode, propose an explicit all-agent map and wait for its approval. Edit only agent-editable files
through individually approved native operations. The guard rejects every other target. If scope must
grow, stop for a new map. Inspect the real diff and leave later gates incomplete until observed.
Once implementation is present, run
`"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" checkpoint-require`; the post-edit hook does
this automatically for native edits. Inspect the diff, then ask one open-ended quiz about a
load-bearing decision and failure mode. Wait for a satisfactory answer before requesting
`"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" checkpoint-pass developer-confirmed`; no answer
leaves every other DuckTutor command locked.
