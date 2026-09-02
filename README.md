# 🦆 DuckTutor

**A Socratic AI pair tutor that keeps the developer responsible for the code**

DuckTutor gives concise guidance for understanding a codebase, reasoning through an issue, and
reviewing what changed. For each task, it separates learner-owned files from agent-editable support
files. By default, you write the load-bearing implementation; explicit `/implement` requests may
change approved files with your approval.

DuckTutor supports both **Claude Code** and **Codex** from the same repository and tutoring skill.

The goal is less AI brainrot: use AI to accelerate learning and feedback without outsourcing your
technical judgment.

## The contract

- DuckTutor reads and explains the project.
- DuckTutor may research links and external facts supplied by the user or required by the task.
- DuckTutor recommends the smallest adequate change and mentions alternatives only when they matter.
- DuckTutor is concise by default and expands when complexity, risk, or your request requires it.
- DuckTutor explains learner-owned code without dictating a transcription-ready solution.
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
  satisfactorily, other DuckTutor commands remain locked.
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

### `/ducktutor:explain <issue URL or problem description>`

Understand the problem, choose the smallest approach, answer one meaningful prediction, and approve
which files you will write versus which support files DuckTutor may edit.

```text
/ducktutor:explain https://github.com/org/repo/issues/123
/ducktutor:explain "Users can submit the form twice on a slow connection"
```

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

### `/ducktutor:checkpoint [optional file, path, or concept]`

Explain a load-bearing decision in your own words using the actual diff and observed behavior.

### `/ducktutor:implement [--force-agent] <problem or feature and optional file scope>`

After using any other DuckTutor command, start or continue implementation. DuckTutor establishes any
missing learning gates, guides learner-owned work, and may edit only approved agent-editable files.
Every edit needs approval and ends with a required open-ended comprehension quiz.

With `--force-agent`, DuckTutor may implement every file in a newly approved all-agent map. The flag
is rejected until another DuckTutor command has run and never authorizes unscoped or destructive edits.

## Codex skill

Codex can load the tutor automatically when a request matches its purpose, or you can invoke it
explicitly:

```text
$ducktutor:tutor Teach me how this repository works.
$ducktutor:tutor Explain this issue and guide me through the smallest adequate fix.
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

1. Start with `/ducktutor:explain` in Claude Code or `$ducktutor:tutor` in Codex.
2. Reason through one prediction gate and approve the learner/agent ownership map.
3. Write the learner-owned implementation; use `/ducktutor:implement` for approved support files.
4. Let DuckTutor perform scoped MCP-assisted end-to-end observation when a suitable tool is
   available, and run any remaining shell test command yourself.
5. Run `/ducktutor:review` on the actual changes.
6. Answer the required open-ended quiz about the edited change; other DuckTutor commands remain
   locked until DuckTutor confirms the answer.
7. Revise or reject the change when understanding or evidence is weak.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE)
