---
description: Implement the prepared task in guided hybrid mode or explicitly assign every approved file to the agent.
argument-hint: "[--force-agent] [problem or feature and optional file scope]"
allowed-tools: Read Glob Grep WebFetch WebSearch Edit Write AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
hooks:
  PreToolUse:
    - matcher: "*"
      hooks:
        - type: command
          command: '"${CLAUDE_PLUGIN_ROOT}"/hooks/guard.sh tool'
  PostToolUse:
    - matcher: "Write|Edit|ApplyPatch|apply_patch"
      hooks:
        - type: command
          command: '"${CLAUDE_PLUGIN_ROOT}"/hooks/post-edit.sh'
---

# DuckTutor · implement

Use the **tutor** skill. For exact token `--force-agent`, remove it from the task and run
`"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" enter implement --force-agent`; otherwise run
the same command without the flag. Stop if rejected. A prior non-implement DuckTutor command unlocks
implementation. Read state before source. Use the prepared task when arguments contain no task text.
If task, prediction, or ownership is missing, establish it here using configured `responseMode`;
do not redirect.

In hybrid mode, do not dictate or edit learner-owned files. In force-agent mode, propose an all-agent
map and await approval; its checkpoint requires deep reflection. Edit only agent-editable files
through approved native operations; reapprove scope growth, which also requires deep reflection.
Inspect the real diff and leave unobserved gates incomplete.

After implementation, run `"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" checkpoint-require`;
native edits do this automatically. Inspect the diff and run the configured checkpoint. After it
passes, request the mode-matched `checkpoint-pass` through the harness.
While pending, only `/checkpoint` and fresh `/start` remain.
