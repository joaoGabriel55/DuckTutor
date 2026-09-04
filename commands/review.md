---
description: Review your actual changes for correctness, proportionality, unnecessary abstraction, and understanding—without modifying them.
argument-hint: "[optional file or path]"
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

# DuckTutor · review

Use the **tutor** skill; never edit. Run
`"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" enter review`; stop if rejected. Read state, then
review `$ARGUMENTS` or the staged and unstaged diff. If none exists, offer single-select next targets.

Check correctness, requirements, failures, tests, scope, abstractions, fit, and assumptions. Flag
`unexplainedAgentChanges` still in the diff. Order findings by severity; give location, consequence,
evidence, and smallest correction. With blockers, ask one guiding question using `responseMode`. Otherwise
state residual risk. Recommend rejecting the diff and restarting from a smaller plan when narrowing
cannot restore confidence. For a disproportionate diff or hidden/system coupling, run
`checkpoint-require deep-reflection` when an implementation task is active; otherwise report the
risk. For other active tasks, run the tutor skill's configured checkpoint. Once passed,
request `"${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" phase assessed assessment-confirmed`.
