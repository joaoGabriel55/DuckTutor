---
description: After a relevant DuckTutor learning command, implement the smallest scoped change with manual approval for every edit.
argument-hint: "<problem or feature and optional file scope>"
allowed-tools: Read Glob Grep WebFetch WebSearch Edit Write AskUserQuestion Skill Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · implement

Use the **tutor** skill. `$ARGUMENTS` must identify the change; otherwise ask for it and stop.

Before inspecting files, confirm the current conversation shows all three prerequisites: a prior
completed DuckTutor guide-only interaction, the same problem or relevant subsystem, and developer
engagement through reasoning, an answer, or an attempted change. If any is missing or compacted
away, state that implementation is locked, recommend `/ducktutor:explain $ARGUMENTS`, and stop. Do
not satisfy the prerequisite and implement in this interaction.

Then inspect the minimum relevant context, declare the exact file scope and purpose, and wait for
approval. Apply only the smallest coherent change through individually approved native edits. If
scope must grow, stop for fresh approval. Inspect the actual diff, remove or flag unrelated lines,
verify what is safely observable, and finish with one comprehension check.
