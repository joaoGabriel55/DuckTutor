# Contributing to DuckTutor

Thanks for helping improve DuckTutor! This guide is about contributing to the **plugin itself**.

## The prime directive

DuckTutor's whole identity is that it **teaches, explains, and proposes — but never implements the solution for the contributor.** Any change to a command's behavior must preserve that guardrail. Every command file (`commands/*.md`) opens with the same "Absolute rule" block; keep it intact and consistent across all commands.

## Project layout

```
ducktutor-plugin/
├── .claude-plugin/
│   ├── plugin.json         # plugin manifest
│   └── marketplace.json    # makes this repo self-installable (source ".")
├── commands/
│   ├── teach-me.md         # /ducktutor:teach-me
│   ├── explain.md          # /ducktutor:explain
│   └── review.md           # /ducktutor:review
├── README.md
├── CONTRIBUTING.md
└── LICENSE
```

Each command is a Markdown file with YAML frontmatter (`description`, `argument-hint`, `allowed-tools`) followed by the prompt. `$ARGUMENTS` holds the user's input.

## Developing locally

```bash
claude --plugin-dir ./ducktutor-plugin
```

- Run `/reload-plugins` after editing a command to pick up changes.
- Confirm `/ducktutor:teach-me`, `/ducktutor:explain`, and `/ducktutor:review` all appear with their argument hints.

## Before opening a PR

- **Validate the JSON:** both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` must parse
  (`python3 -m json.tool < .claude-plugin/plugin.json`).
- **Guardrail test:** invoke each command and ask it to "just write the code for me." It must decline and explain the approach instead — never emit implementation code, snippets, or diffs.
- **Smoke test:** run each command in a real repo and confirm the behavior matches its description.
- Keep the "Absolute rule" block identical across all command files if you change it.
- Bump the `version` in both `plugin.json` and `marketplace.json` for user-facing changes.

## Reporting issues

Open an issue describing the command, what you expected, and what happened. Include the exact invocation where possible.
