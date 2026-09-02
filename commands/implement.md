---
description: Guide learner-owned work and implement only approved agent-editable support files.
argument-hint: "<problem or feature and optional file scope>"
allowed-tools: Read Glob Grep WebFetch WebSearch Edit Write AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · implement

Use the **tutor** skill and require `$ARGUMENTS`. Run `learning-state.sh show` before inspecting source.
Proceed only for the same non-stale active task in `predicted` or `attempted` with an approved ownership map.
Otherwise stop and recommend `/ducktutor:explain`.

Restate both file lists. The developer writes learner-owned files; do not dictate or edit them. Edit
only agent-editable files through individually approved native operations. The guard rejects every
other target. If scope must grow, stop for a new map. Inspect the real diff, record the learner's
attempt when present, and leave verification and explain-it-back gates incomplete until observed.
