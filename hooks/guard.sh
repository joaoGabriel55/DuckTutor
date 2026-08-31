#!/usr/bin/env bash

set -uo pipefail

MODE="${1:-}"
PAYLOAD="$(cat 2>/dev/null || true)"

deny() {
  local reason="$1"
  REASON="$reason" node -e '
    const reason = process.env.REASON || "DuckTutor blocked this action.";
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason
      }
    }) + "\n");
  '
  exit 0
}

ask() {
  local reason="$1"
  REASON="$reason" node -e '
    const reason = process.env.REASON || "DuckTutor requires your approval.";
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: reason
      }
    }) + "\n");
  '
  exit 0
}

extract_field() {
  local field="$1"
  printf '%s' "$PAYLOAD" | FIELD="$field" node -e '
    let input = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", chunk => input += chunk);
    process.stdin.on("end", () => {
      try {
        const payload = JSON.parse(input);
        const field = process.env.FIELD;
        const value = field === "command" ? payload?.tool_input?.command : payload?.[field];
        process.stdout.write(typeof value === "string" ? value : "");
      } catch (_) {
        process.exit(1);
      }
    });
  '
}

check_bash() {
  local command
  command="$(extract_field command 2>/dev/null || true)"
  if [[ -z "$command" ]]; then
    deny "DuckTutor could not verify this shell command as read-only, so it was blocked."
  fi

  if [[ "$command" == *$'\n'* || "$command" == *';'* || "$command" == *'|'* ||
        "$command" == *'&'* || "$command" == *'>'* || "$command" == *'<'* ||
        "$command" == *'`'* || "$command" == *'$('* ]]; then
    deny "DuckTutor blocks shell composition and redirection. Run mutation-capable commands yourself and share the output for review."
  fi

  case "$command" in
    git\ diff|git\ diff\ *|git\ log|git\ log\ *|git\ show|git\ show\ *)
      if [[ "$command" == *'--output'* || "$command" == *'--ext-diff'* ||
            "$command" == *'--textconv'* ]]; then
        deny "DuckTutor blocked a Git inspection command with an output or executable-transform option."
      fi
      return 0
      ;;
    git\ status|git\ status\ *|git\ branch\ --show-current|git\ rev-parse\ *|git\ remote\ -v|git\ remote\ get-url\ *|git\ ls-files|git\ ls-files\ *|gh\ issue\ view\ *)
      return 0
      ;;
    *)
      deny "DuckTutor only runs read-only Git inspection and GitHub issue-view commands. Run build, test, formatting, and mutation-capable commands yourself, then share their output."
      ;;
  esac
}

case "$MODE" in
  tool)
    TOOL_NAME="$(extract_field tool_name 2>/dev/null || true)"
    case "$TOOL_NAME" in
      Read|Glob|Grep|WebFetch|WebSearch|web__run|web.run|AskUserQuestion|request_user_input|Skill|update_plan)
        exit 0
        ;;
      Bash)
        check_bash
        exit 0
        ;;
      Write|Edit|NotebookEdit|MultiEdit|ApplyPatch|apply_patch)
        ask "DuckTutor never auto-approves edits. Approve only if this file is in the explicitly agreed problem scope and the proposed change is the smallest adequate edit."
        ;;
      "")
        deny "DuckTutor could not identify this tool, so the scoped default-deny guard blocked it."
        ;;
      *)
        deny "DuckTutor blocks tools outside its scoped tutoring set, including subagents and external mutation tools."
        ;;
    esac
    ;;
  file)
    ask "DuckTutor never auto-approves edits. Approve only if this file is in the explicitly agreed problem scope and the proposed change is the smallest adequate edit."
    ;;
  bash)
    check_bash
    exit 0
    ;;
  *)
    deny "DuckTutor blocked an unrecognized mutation guard request."
    ;;
esac
