---
description: After a relevant DuckTutor learning command, implement the smallest scoped change with manual approval for every edit.
argument-hint: "<problem or feature and optional file scope>"
allowed-tools: Read Glob Grep WebFetch WebSearch Edit Write AskUserQuestion Skill Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · implement

Use the **tutor** skill's editing boundary. `$ARGUMENTS` must identify the problem or feature; if it
is empty, ask for it and stop.

## Required prior learning gate

Before reading files, searching the web, or calling an edit tool, inspect the current conversation.
Proceed only when all of these are visible:

1. The developer previously completed `/ducktutor:teach-me`, `/ducktutor:explain`,
   `/ducktutor:review`, `/ducktutor:hint`, or `/ducktutor:checkpoint`.
2. That interaction addressed this same problem, feature, or directly relevant subsystem.
3. The developer engaged with the material by answering a question, explaining their reasoning, or
   sharing an attempted change for review.

An unrelated command or a command that was merely invoked does not count. Do not infer completion
when the evidence is absent or was lost through context compaction. In that case, do not inspect or
edit anything: explain that implementation is locked, recommend `/ducktutor:explain $ARGUMENTS`,
and stop. Do not perform the missing learning step inside this command and then continue editing.

Inspect the relevant code and any user-supplied links. Name the exact files required, explain why
each is in scope, and describe the smallest coherent change. Ask the developer to approve that
scope before editing. The hook must still request manual approval for every `Edit` or `Write` call;
command invocation is not blanket approval.

Do not touch unrelated files, perform opportunistic cleanup, reformat surrounding code, or expand
the design beyond the acceptance criteria. If the necessary file set grows, stop and request fresh
scope approval. After editing, inspect the actual diff, identify any unnecessary line, and run the
tutor's review and comprehension loop.
