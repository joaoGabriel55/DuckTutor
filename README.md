# 🦆 DuckTutor

**A Socratic AI pair tutor that keeps the developer responsible for the code**

DuckTutor helps you understand a codebase, research relevant context, reason through an issue, and
review what actually changed. It normally guides you while you edit. When you explicitly choose the
manual implementation command, it may make the smallest scoped change, but every edit operation still
requires your approval. Afterward, DuckTutor reviews the real diff and checks whether you can
explain it.

DuckTutor supports both **Claude Code** and **Codex** from the same repository and tutoring skill.

The goal is less AI brainrot: use AI to accelerate learning and feedback without outsourcing your
technical judgment.

## The contract

- DuckTutor reads and explains the project.
- DuckTutor may research links and external facts supplied by the user or required by the task.
- DuckTutor compares approaches and recommends the smallest adequate change.
- DuckTutor may show one focused code chunk at a time for manual application.
- Editing is available only after a relevant DuckTutor learning command in which you engaged with
  the problem, followed by an explicit implementation request.
- Every edit operation is manually approved; DuckTutor never enables automatic editing.
- Only files directly required by the described problem or feature may be changed.
- DuckTutor reviews the actual Git diff, not merely its earlier suggestion.
- DuckTutor may use host-configured MCP tools for scoped end-to-end observation and testing.
- MCP calls remain subject to the host's server and per-tool permission policy and never bypass the
  source-editing boundary.
- Every interaction ends with a purposeful question; completed changes get an explain-it-back gate
  and an adaptive quiz.
- DuckTutor never hides a write inside shell commands or expands into unrelated cleanup.

> **Manual means manual:** DuckTutor's default-deny hook allows read/search tools and narrowly
> validated Git inspection. Native file-edit tools always escalate to you for approval—even if your
> host normally auto-accepts edits. Canonically named MCP tools defer to your host's MCP permission
> policy so DuckTutor can perform scoped verification; they cannot be used to edit source files.
> The shell gate also permits `ls`, `cat`, inspection-only `find`, read-only `git config`, and
> `gh issue view`/`gh pr view`. Shell-based writes, arbitrary commands, subagents, and unknown future
> tools remain blocked.

## Why

Code that runs can still be a poor engineering decision. DuckTutor asks you to reconsider a change
when you cannot explain it, the diff is larger than the problem, it adds abstractions without
evidence, or it makes the system harder to reason about.

Manual copy/paste alone does not create understanding, so DuckTutor combines it with prediction,
review of the applied change, observable verification, active recall, and explain-it-back.

The approach is inspired by:

- [When I reject AI code even if it works](https://vinibrasil.com/when-i-reject-ai-code-even-if-it-works/)
  by Vinicius Brasil.
- [Demonkey](https://github.com/geeksilva97/demonkey), especially its constrained Socratic loop,
  progressive hints, developer-owned code, local verification, and adaptive consolidation quizzes.

## Claude Code commands

### `/ducktutor:teach-me [optional topic or subsystem]`

Build a grounded mental model of the whole project or one subsystem, then answer a diagnostic
question.

```text
/ducktutor:teach-me
/ducktutor:teach-me authentication
```

### `/ducktutor:explain <issue URL or problem description>`

Understand the problem, compare approaches, answer a prediction question, and receive minimal code
chunks to apply manually. DuckTutor inspects your real diff after each applied stage.

```text
/ducktutor:explain https://github.com/org/repo/issues/123
/ducktutor:explain "Users can submit the form twice on a slow connection"
```

### `/ducktutor:review [optional file or path]`

Review the current working diff or a selected target for correctness, scope, abstractions,
reasonability, tests, and project fit. Clean reviews finish with explain-it-back and a quiz.

```text
/ducktutor:review
/ducktutor:review src/api/handlers.ts
```

### `/ducktutor:hint [problem, error, file, or symbol]`

Get the smallest useful nudge. Hints escalate from a code pointer and leading question to a partial
skeleton or focused copyable snippet only when needed.

### `/ducktutor:checkpoint [optional file, path, or concept]`

Test your understanding of an applied change using its actual diff and behavior.

### `/ducktutor:implement <problem or feature and optional file scope>`

Continue from a relevant completed `/teach-me`, `/explain`, `/review`, `/hint`, or `/checkpoint`
interaction in the current conversation. You must have engaged with that earlier step; an unrelated
or merely invoked command does not unlock editing. DuckTutor then names the exact files, asks you to
approve the scope and every edit operation, and never touches unrelated files.

## Codex skill

Codex can load the tutor automatically when a request matches its purpose, or you can invoke it
explicitly:

```text
$ducktutor:tutor Teach me how this repository works.
$ducktutor:tutor Explain this issue and guide me through the smallest adequate fix.
$ducktutor:tutor Implement this feature with manual approval for every scoped edit operation.
$ducktutor:tutor Review my current diff and check whether I understand it.
```

The same scope and approval hook protects Codex tool calls. Codex asks you to review and trust plugin
hooks before enabling them; the protection is inactive until the hook is trusted.

## MCP-assisted verification

DuckTutor can use MCP servers that you have already configured in Claude Code or Codex. It does not
bundle, install, or require a particular server: browser automation, developer tools, and other test
adapters remain your choice. When a host exposes a tool using the canonical
`mcp__<server>__<tool>` name, DuckTutor's guard defers that call to the host's own server and
per-tool permission settings.

During a scoped feature, fix, or review, DuckTutor may use an available MCP tool to navigate a local
or test application, exercise the relevant flow, inspect page state, console output, or network
activity, and capture snapshots or screenshots. It reports the target, actions, expectation, and
observed result. MCP tools never replace the learning gate, native edit approval, actual diff
review, or explain-it-back checkpoint.

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

Use `/reload-plugins` after editing plugin files. Use `/hooks` to confirm DuckTutor's `PreToolUse`
guards are loaded.

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
2. Reason through the prediction gate and answer the command's learning question.
3. Apply the suggestion yourself, or continue in the same conversation with
   `/ducktutor:implement` and approve its exact file scope and each edit.
4. Let DuckTutor perform scoped MCP-assisted end-to-end observation when a suitable tool is
   available, and run any remaining shell test command yourself.
5. Run `/ducktutor:review` on the actual changes.
6. Explain the load-bearing decisions and complete the checkpoint.
7. Revise or reject the change when understanding or evidence is weak.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE)
