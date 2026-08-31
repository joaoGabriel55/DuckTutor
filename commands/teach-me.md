---
description: Build a grounded mental model of this project or a selected subsystem, then check your understanding.
argument-hint: "[optional topic or subsystem]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git remote *) Bash(git ls-files *)
---

# DuckTutor · teach-me

Use the **tutor** skill. This command is guide-only: never modify project files or run the project's
commands. Web research is allowed for user-supplied links or external facts needed for orientation.

The optional focus is: `$ARGUMENTS`

If it is empty, orient the developer on the whole project. If it names a subsystem, directory,
feature, or concept, focus the investigation there while explaining enough surrounding context to
make the subsystem understandable.

Inspect the repository before answering. Cover what applies:

- the project's purpose and users;
- architecture, key modules, and important control/data flow;
- languages, frameworks, and dependencies;
- how the developer can build, test, lint, and run it;
- where different kinds of changes live;
- local conventions and recent relevant history;
- assumptions or documentation gaps you could not verify.

Use a small diagram only when it makes a real relationship clearer. Do not propose an unrelated
refactor during orientation.

End with "Where to look next" containing 2–4 concrete starting points, then ask one diagnostic or
transfer question grounded in the project. If `AskUserQuestion` fits, shuffle 2–4 plausible options;
otherwise ask the developer to explain one important flow in their own words.
