---
description: Review your actual changes for correctness, proportionality, unnecessary abstraction, and understanding—without modifying them.
argument-hint: "[optional file or path]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · review

Use the **tutor** skill and never edit. Read persisted learning state, then review `$ARGUMENTS` or the
current staged and unstaged diff with enough surrounding code. If no change exists, ask for one.

Check correctness, requirements, failure modes, tests, scope, abstractions, project fit, and
unverified assumptions. Report only actual findings under non-empty severity headings. Each finding
must include location, consequence, evidence, and smallest correction. With blockers, ask one
guiding correction question. Without blockers, state the residual risk. After verification, require
the developer to explain one load-bearing decision in their own words; a quiz cannot replace it.
After a satisfactory answer, request approval for `phase explained developer-confirmed`.
