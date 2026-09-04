---
description: Check understanding using the configured response mode or abandon the pending task.
argument-hint: "[--abandon | optional file, path, or concept]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
hooks:
  PreToolUse:
    - matcher: "*"
      hooks:
        - type: command
          command: '"${CLAUDE_PLUGIN_ROOT}"/hooks/guard.sh tool'
  PostToolUse:
    - matcher: "Write|Edit|ApplyPatch|apply_patch"
      hooks:
        - type: command
          command: '"${CLAUDE_PLUGIN_ROOT}"/hooks/post-edit.sh'
---

# DuckTutor · checkpoint

Use the **tutor** skill; run `"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" enter checkpoint`.
For `--abandon`, show task and time, state no assessment is recorded, and ask one choice
confirmation. If confirmed, run
`"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" checkpoint-abandon choice-confirmed` and stop.

Inspect state and diff. If the diff is disproportionate or introduces hidden/system coupling, run
`checkpoint-require deep-reflection`. This risk escalation overrides a quiz preference. Otherwise,
in quiz mode run the tutor skill's adaptive quiz. After each choice, run
`"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" checkpoint-record <correct|incorrect|unsure>`.
For multi-select, record correct only when the response matches every correct option and no incorrect
option; `I'm unsure` cannot be combined with another choice.
Keep the checkpoint pending unless two answers are correct within three. After three without a pass,
run `checkpoint-require` through the harness for a fresh attempt.
In free-text or deep-reflection mode, ask for the load-bearing decision and failure mode in the
developer's own words; correct misconceptions. Run `checkpoint-pass` with `free-text-confirmed`,
then `"${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" phase assessed assessment-confirmed`.
Call the result evidence, not proof of understanding. Never edit.
