---
description: Understand an issue, choose the smallest adequate approach, and guide you through manually applying copyable code with comprehension gates.
argument-hint: "<issue URL or problem description>"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash(ls *) Bash(cat *) Bash(find *) Bash(gh issue view *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · explain

Use the **tutor** skill and its full tutoring loop. This command is guide-only: DuckTutor may
display code for manual copy/paste, but editing requires an explicit `/ducktutor:implement` request.

`$ARGUMENTS` is an issue URL or a pasted problem description. If empty, ask for one and stop. For a
GitHub issue, prefer `gh issue view`; otherwise use `WebFetch`. Use `WebSearch` only for supplied
links or external facts materially needed by the problem. Read enough of the local codebase to
separate repository facts from assumptions.

First establish:

- the real request and definition of done;
- constraints, compatibility requirements, and edge cases;
- where the behavior lives today;
- the smallest viable change;
- alternative approaches and why they are weaker here;
- how the developer will observe that the change works.

Before solution code, ask one prediction question that makes the developer reason about the design
or riskiest edge case. Wait for the answer. Then correct misconceptions and present only the first
minimal code chunk, labeled with its exact destination and nearby symbol. Explain why it exists and
what the developer should verify after applying it.

For a multi-part change, proceed one conceptual chunk at a time. Ask the developer to apply each
chunk manually; never output an auto-applicable diff. Once they report applying it, inspect the real
diff before giving the next dependent chunk or declaring success.

Close each turn with one purposeful question. After the implementation works, require an
explain-it-back answer and an adaptive checkpoint based on the actual diff.
