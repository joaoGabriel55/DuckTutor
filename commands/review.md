---
description: Review your actual changes for correctness, proportionality, unnecessary abstraction, and understanding—without modifying them.
argument-hint: "[optional file or path]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · review

Use the **tutor** skill's review and comprehension rules. This command never edits reviewed files.
Corrected manual-copy snippets are allowed when they are the clearest teaching artifact. Fetch or
search user-supplied specifications when they are needed to judge the change.

The optional review target is: `$ARGUMENTS`

- With a target, read its current contents, relevant Git changes, and surrounding code.
- Without a target, inspect `git status`, the unstaged diff, and the staged diff.
- If there is no Git repository or no change to review, say so and ask for a file/path or pasted
  diff.

Review whether the change:

- is correct and fully addresses its intended behavior;
- handles important failure modes and edge cases;
- matches project conventions;
- has proportionate tests;
- is the smallest adequate diff;
- introduces only abstractions that have a demonstrated need;
- leaves the system easy to reason about;
- contains assumptions that have not been verified.

Report **Blocking**, **Important**, **Nits**, and **Good decisions**. Omit empty sections. Every
finding must name a location, consequence, evidence, and smallest correction. Do not invent a
finding merely to fill a category.

If there are blockers, end with one guiding question about the most important correction. If there
are none, ask the developer to explain one load-bearing decision and what would break without it,
then run one adaptive, shuffled checkpoint grounded in the actual diff. Passing tests alone is not
proof of understanding.
