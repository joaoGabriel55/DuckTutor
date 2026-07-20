# 🦆 DuckTutor

**A rubber-duck tutor for open source contributors**

DuckTutor helps you *understand* the project you're contributing to, *understand* the issue you're solving, and get *guided feedback* on your own work. It will happily explain a problem and even propose a solution approach — but it will **never write the code for you**.

> 🧩 **Using a different AI coding tool?** Versions of DuckTutor for **Codex** and **Antigravity** are **coming soon** — same teach / explain / review workflow, same "never writes the code for you" rule.

## Why

It's easy to let an AI write your patch, ship code you don't understand, and slowly rot your own skills. DuckTutor is the opposite of that. It's a tutor, not an autopilot:

- ✅ It teaches you the codebase, explains issues, and proposes solution *approaches* with the reasoning behind them.
- ❌ It never hands you the finished code — no solution snippets, no diffs, no "paste this."

You write 100% of the code. DuckTutor makes sure you know *why*.

## Commands

### `/ducktutor:teach-me [optional topic or subsystem]`
Orients you on the project: what it does and its goals, the architecture, the tech stack, how to build/test/run, where things live, and its conventions. Pass a topic to deep-dive one subsystem.

```
/ducktutor:teach-me
/ducktutor:teach-me auth
```

### `/ducktutor:explain <issue URL or problem description>`
Reads an issue (URL or pasted markdown), explains the problem in depth, then proposes a solution approach — files to touch, steps in prose, and the reasoning/trade-offs. Never as implementation code.

```
/ducktutor:explain https://github.com/org/repo/issues/123
/ducktutor:explain "Users can submit the form twice on a slow connection..."
```

### `/ducktutor:review [optional file or path]`
Reviews your changes and guides you to fix issues yourself. With no argument it inspects your working git diff; pass a path to review a specific file. Feedback and reasoning only — never the corrected code.

```
/ducktutor:review
/ducktutor:review src/api/handlers.ts
```

## Installation

**From the marketplace** (this repo is its own marketplace):

```bash
claude plugin marketplace add <user>/ducktutor-plugin
claude plugin install ducktutor@ducktutor
```

**For local development / trying it out:**

```bash
claude --plugin-dir ./ducktutor-plugin
```

Then use `/reload-plugins` to pick up changes without restarting.

## The one rule

> DuckTutor may **propose and fully explain** a solution, but it must **never implement it for you**. The contributor writes every line. If you ask it to "just write the code," it will decline and explain the approach instead — so *you* can write it.

## Other AI coding tools

DuckTutor starts on Claude Code, but it isn't meant to stay there. Versions for other AI coding assistants are on the way — same tutor, same `teach-me` / `explain` / `review` workflow, and the same "propose and explain, never implement" rule. Only the packaging changes to fit each tool.

| Tool | Status |
| --- | --- |
| **Claude Code** | ✅ Available (this repo) |
| **Codex** | 🚧 Coming soon |
| **Antigravity** | 🚧 Coming soon |

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE)
