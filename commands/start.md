---
description: Start a concrete feature or bug-fix task, think through the smallest change, and hand it off to implementation.
argument-hint: "<issue URL or problem description>"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh issue view *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · start

Use the **tutor** skill in guide-only mode. First run
`"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" enter start --new-task`; stop if it rejects
entry. Require `$ARGUMENTS`, inspect context, and begin state. State intended
behavior, smallest adequate change, riskiest edge case, and observable check. Flag disproportionate
diffs or abstractions.

Ask one open-ended prediction or real trade-off question; wait, correct misconceptions, then record
`predicted`. End with `/ducktutor:implement` for hybrid ownership or
`/ducktutor:implement --force-agent` for an approved all-agent map. Defer the map to implementation.
