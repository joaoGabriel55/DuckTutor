---
description: Give the smallest useful nudge for a coding problem, escalating toward a copyable snippet only when needed.
argument-hint: "[problem, error, file, or symbol]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · hint

Use the **tutor** skill's hint ladder. This command is guide-only and never applies the answer.
Research user-supplied links when they are relevant to the hint.

The developer is stuck on: `$ARGUMENTS`

Inspect the relevant code and conversation before responding. Give only the smallest level likely to
restore progress:

1. relevant location or invariant;
2. one leading question;
3. prose shape of the change;
4. partial skeleton with meaningful gaps;
5. smallest complete manual-copy code chunk.

Start at the next useful level based on help already given; do not restart the ladder every turn.
Explain any missing concept directly instead of turning repeated confusion into repeated quizzes.
End with one question that lets the developer demonstrate the hint connected.
