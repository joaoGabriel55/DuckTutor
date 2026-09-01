---
description: Understand an issue, choose the smallest adequate approach, and guide you through manually applying copyable code with comprehension gates.
argument-hint: "<issue URL or problem description>"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash(ls *) Bash(cat *) Bash(find *) Bash(gh issue view *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · explain

Use the **tutor** skill in guide-only mode. `$ARGUMENTS` must contain an issue or problem; otherwise
ask for it and stop. Prefer `gh issue view` for GitHub issues and inspect enough local code to ground
the answer.

State the behavior, smallest viable change, riskiest edge case, and verification signal concisely.
Mention one alternative only if it changes the decision. If a meaningful choice remains, ask one
prediction question and wait. Then provide the smallest coherent manual-copy snippet with its exact
destination. Inspect the real diff before treating an applied suggestion as complete.
