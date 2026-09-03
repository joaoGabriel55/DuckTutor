# 🦆 DuckTutor

**A Socratic AI pair tutor that keeps the developer responsible for the code**

DuckTutor gives concise guidance for understanding a codebase, starting a concrete feature or fix,
and reviewing what changed. `/start` turns a problem description or issue into a small, grounded
implementation handoff. For each task, DuckTutor separates learner-owned files from agent-editable
support files. By default, you write the load-bearing implementation; explicit `/implement` requests
may change approved files with your approval.

DuckTutor supports both **Claude Code** and **Codex** from the same repository and tutoring skill.

The goal is less AI brainrot: use AI to accelerate learning and feedback without outsourcing your
technical judgment.

## The contract

- DuckTutor reads and explains the project.
- DuckTutor may research links and external facts supplied by the user or required by the task.
- DuckTutor recommends the smallest adequate change and mentions alternatives only when they matter.
- DuckTutor is concise by default and expands when complexity, risk, or your request requires it.
- DuckTutor explains learner-owned code without dictating a transcription-ready solution.
- `/start` grounds a new feature or bug fix, asks for one meaningful human judgment, and then hands
  off directly to `/implement` without making you repeat the task.
- `/explain` is for understanding code or behavior and does not silently create task state.
- Any prior non-implementation DuckTutor command unlocks an explicit `/implement` request; missing
  task, prediction, and ownership gates are completed inside that flow.
- `/implement --force-agent` allows an approved all-agent map only after that prior tutoring command.
- Each task has an approved learner-owned/agent-editable file map persisted in Git metadata.
- DuckTutor may edit only agent-editable files through manually approved native edit operations.
- Learner-owned and unscoped files are mechanically blocked.
- DuckTutor reviews the actual Git diff, not merely its earlier suggestion.
- DuckTutor may use host-configured MCP tools for scoped end-to-end observation and testing.
- MCP calls remain subject to the host's server and per-tool permission policy and never bypass the
  source-editing boundary.
- After DuckTutor edits, an open-ended comprehension quiz is mandatory. Until it is answered
  satisfactorily, other DuckTutor commands remain locked except for an explicit fresh `/start`.
- A pending task may be explicitly abandoned through `/checkpoint --abandon`; this records no
  understanding and requires confirmation. Starting a fresh task also retires the old task without
  recording understanding; its agent-edited paths remain marked for later review while still present
  in the working diff.
- DuckTutor never hides a write inside shell commands or expands into unrelated cleanup.

> **Hybrid ownership is enforced:** DuckTutor's default-deny hook checks native edits against the
> active ownership map. Agent-editable files still require approval; learner-owned and unscoped files
> are denied. Browser/test MCP tools remain available, MCP file mutation is denied, and unknown MCP
> capabilities require approval.
> The shell gate also permits `ls`, `cat`, inspection-only `find`, read-only `git config`, and
> `gh issue view`/`gh pr view`. Shell-based writes, arbitrary commands, subagents, and unknown future
> tools remain blocked.

## Why

Code that runs can still be a poor engineering decision. DuckTutor asks you to reconsider a change
when you cannot explain it, the diff is larger than the problem, it adds abstractions without
evidence, or it makes the system harder to reason about.

Copying code does not create understanding, so DuckTutor combines learner-written implementation
with prediction, review of the applied change, observable verification, and explain-it-back.

The approach is inspired by:

- [When I reject AI code even if it works](https://vinibrasil.com/when-i-reject-ai-code-even-if-it-works/)
  by Vinicius Brasil.
- [Demonkey](https://github.com/geeksilva97/demonkey), especially its constrained Socratic loop,
  progressive hints, developer-owned code, local verification, and adaptive consolidation quizzes.

## Claude Code commands

### `/ducktutor:teach-me [optional topic or subsystem]`

Build a concise mental model of the whole project or one subsystem, with a diagnostic question when
it helps.

```text
/ducktutor:teach-me
/ducktutor:teach-me authentication
```

### `/ducktutor:start <issue URL or problem description>`

Start a concrete feature or bug fix. DuckTutor inspects enough context to state the intended
behavior, smallest adequate approach, riskiest edge case, and verification signal, then asks one
open-ended prediction or trade-off question. After your answer, run `/ducktutor:implement` for guided
hybrid work or `/ducktutor:implement --force-agent` for an approved all-agent scope. You do not need
to repeat the task description.

Each explicit `/start` creates fresh task state, so an older task and ownership map cannot leak into
the new request. If the older task has a pending comprehension checkpoint, `/start` retires it
without claiming understanding and begins fresh.

```text
/ducktutor:start https://github.com/org/repo/issues/123
/ducktutor:start "Users can submit the form twice on a slow connection"
```

### `/ducktutor:explain <code, behavior, issue, or concept>`

Understand how something works without starting a task, assigning files, or changing code. Use
`/start` instead when the intent is to build or fix.

### `/ducktutor:review [optional file or path]`

Review the current working diff or a selected target for correctness, scope, abstractions,
reasonability, tests, and project fit. Clean reviews use one change-grounded comprehension check.

```text
/ducktutor:review
/ducktutor:review src/api/handlers.ts
```

### `/ducktutor:hint [problem, error, file, or symbol]`

Get the smallest useful nudge. Hints escalate from a code pointer and leading question to a partial
skeleton, without dictating learner-owned code.

### `/ducktutor:checkpoint [--abandon | optional file, path, or concept]`

Explain a load-bearing decision in your own words using the actual diff and observed behavior.
Checkpoints persist across sessions. If the task is no longer relevant, `--abandon` shows which task
will be discarded, requires confirmation, records the abandonment, and clears its ownership map.

### `/ducktutor:implement [--force-agent] [problem or feature and optional file scope]`

After `/start`, begin implementation without repeating the task. DuckTutor establishes any missing
learning gates, guides learner-owned work, and may edit only approved agent-editable files. You can
also supply a task directly after using another DuckTutor command. Every edit needs approval and
ends with a required open-ended comprehension quiz.

With `--force-agent`, DuckTutor may implement every file in a newly approved all-agent map. The flag
is rejected until another DuckTutor command has run and never authorizes unscoped or destructive edits.

## Codex skill

Codex can load the tutor automatically when a request matches its purpose, or you can invoke it
explicitly:

```text
$ducktutor:tutor Teach me how this repository works.
$ducktutor:tutor Start this issue as a minimal, grounded implementation task.
$ducktutor:tutor Explain how this subsystem works without changing it.
$ducktutor:tutor Implement this feature with manual approval for every scoped edit operation.
$ducktutor:tutor Review my current diff and check whether I understand it.
```

The same state and ownership hooks protect Codex tool calls. Codex asks you to review and trust plugin
hooks before enabling them; protection and automatic session restore are inactive until trusted.

## Project-native context

At session start, DuckTutor inventories paths—not contents—for applicable `AGENTS.md`, `AGENTS.override.md`, `CLAUDE.md`,
and `CONTEXT.md` files, project skills under `.agents/`, `.codex/`, or `.claude/`, hook and MCP
configuration, CI workflows, and common build manifests. It reads only what the current task needs,
uses matching skills through the host, and respects project hooks and instructions without copying
their contents into learning state. Project context can narrow behavior but cannot expand tool
permissions, file ownership, or user authorization.

## Persistent learning state

DuckTutor stores one active task per Git repository under `.git/ducktutor/state.json`, so it does not
dirty the working tree. The state records the task, ownership map, and current phase:
`grounded → predicted → attempted → verified → explained`. It also records command engagement and
whether a comprehension checkpoint is pending. A session-start hook restores a compact summary after
startup, resume, clear, or context compaction. State records progress; it does not prove
understanding or replace inspection of the current diff. The map cannot be used while another branch
is checked out or when rewritten history no longer descends from its approved baseline. DuckTutor
then requires fresh inspection and ownership-map approval before editing.

## MCP-assisted verification

DuckTutor can use MCP servers that you have already configured in Claude Code or Codex. It does not
bundle, install, or require a particular server: browser automation, developer tools, and other test
adapters remain your choice. When a host exposes a tool using the canonical
`mcp__<server>__<tool>` name, DuckTutor classifies observation/testing operations separately from
file mutation. Unknown capabilities use the host's explicit approval flow.

During a scoped feature, fix, or review, DuckTutor may use an available MCP tool to navigate a local
or test application, exercise the relevant flow, inspect page state, console output, or network
activity, and capture snapshots or screenshots. It reports the target, actions, expectation, and
observed result. MCP file-mutation tools are denied. MCP tools never replace the ownership map,
native edit approval, actual diff review, or explain-it-back gate.

## Installation

### Claude Code

From this repository's marketplace:

```bash
claude plugin marketplace add joaoGabriel55/DuckTutor
claude plugin install ducktutor@ducktutor
```

For local development:

```bash
claude --plugin-dir ./DuckTutor
```

Use `/reload-plugins` after editing plugin files. Use `/hooks` to confirm DuckTutor's session,
pre-tool, post-edit, and prompt-gate hooks are loaded.

### Codex

Install DuckTutor from a configured marketplace using the Codex plugin browser (`/plugins`) or the
CLI:

```bash
codex plugin marketplace add <marketplace-source>
codex plugin add ducktutor@<marketplace-name>
```

Start a new Codex thread after installation so the tutor skill and hook are loaded. The repository
contains the Codex package manifest at `.codex-plugin/plugin.json`; adding it to a personal or team
marketplace is intentionally separate from editing this source repository.

## Typical loop

1. Start a feature or fix with `/ducktutor:start <problem>` in Claude Code or `$ducktutor:tutor` in Codex.
2. Reason through one prediction or trade-off question, then choose `/ducktutor:implement` or
   `/ducktutor:implement --force-agent`.
3. Approve the proposed ownership map and implement the scoped change.
4. Let DuckTutor perform scoped MCP-assisted end-to-end observation when a suitable tool is
   available, and run any remaining shell test command yourself.
5. Run `/ducktutor:review` on the actual changes.
6. Answer the required open-ended quiz about the edited change; other DuckTutor commands remain
   locked until DuckTutor confirms the answer. Explicitly abandon an obsolete task through
   `/ducktutor:checkpoint --abandon`, or use `/ducktutor:start <new task>` to retire it and begin
   fresh without claiming understanding.
7. Revise or reject the change when understanding or evidence is weak.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE)
