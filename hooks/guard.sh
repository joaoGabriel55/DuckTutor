#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

check_find() {
  local command="$1"
  local normalized="$command"
  normalized="${normalized//\\/}"
  normalized="${normalized//\'/}"
  normalized="${normalized//\"/}"

  case "$normalized" in
    *-delete*|*-exec*|*-ok*|*-fprint*|*-fprintf*|*-fls*)
      deny "DuckTutor allows find for inspection only. Actions that delete, execute commands, or write files are blocked."
      ;;
  esac
}

check_git_config() {
  local command="$1"
  local normalized="$command"
  local rest arg skip_next=0 positionals=0
  local -a args
  normalized="${normalized//\\/}"
  normalized="${normalized//\'/}"
  normalized="${normalized//\"/}"
  rest="${normalized#git config}"
  read -r -a args <<< "$rest"

  for arg in "${args[@]}"; do
    case "$arg" in
      --add|--replace-all|--unset|--unset-all|--rename-section|--remove-section|--edit|-e|set|unset|rename-section|remove-section|edit)
        deny "DuckTutor allows git config inspection only. Setting, unsetting, renaming, removing, or editing configuration is blocked."
        ;;
    esac
  done

  for arg in "${args[@]}"; do
    case "$arg" in
      --get|--get-all|--get-regexp|--get-urlmatch|--get-color|--get-colorbool|--list|-l|get|get-all|get-regexp|get-urlmatch|list)
        return 0
        ;;
    esac
  done

  for arg in "${args[@]}"; do
    if (( skip_next )); then
      skip_next=0
      continue
    fi

    case "$arg" in
      --file|-f|--blob|--type)
        skip_next=1
        ;;
      --global|--system|--local|--worktree|--includes|--no-includes|--show-origin|--show-scope|--name-only|--null|-z|--fixed-value|--type=*|--bool|--int|--bool-or-int|--bool-or-str|--path|--expiry-date|--color)
        ;;
      --*|-*)
        deny "DuckTutor could not verify this git config option as read-only, so it was blocked."
        ;;
      *)
        positionals=$((positionals + 1))
        ;;
    esac
  done

  if (( skip_next || positionals > 1 )); then
    deny "DuckTutor allows git config inspection only. Supplying a value that could change configuration is blocked."
  fi
}

check_bash() {
  local command state_script state_script_variable state_args state_action context_script context_script_variable harness_script harness_script_variable harness_args
  command="$(extract_field command 2>/dev/null || true)"
  if [[ -z "$command" ]]; then
    deny "DuckTutor could not verify this shell command as read-only, so it was blocked."
  fi

  if [[ "$command" == *$'\n'* || "$command" == *';'* || "$command" == *'|'* ||
        "$command" == *'&'* || "$command" == *'>'* || "$command" == *'<'* ||
        "$command" == *'`'* || "$command" == *'$('* ]]; then
    deny "DuckTutor blocks shell composition and redirection. Run mutation-capable commands yourself and share the output for review."
  fi

  state_script="$ROOT/scripts/learning-state.sh"
  state_script_variable='"${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh"'
  context_script="$ROOT/scripts/project-context.sh"
  context_script_variable='"${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh"'
  harness_script="$ROOT/scripts/command-harness.sh"
  harness_script_variable='"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh"'
  case "$command" in
    "$context_script show"|"\"$context_script\" show"|"$context_script_variable show")
      return 0
      ;;
    "$context_script "*|"\"$context_script\" "*|"$context_script_variable "*)
      deny "DuckTutor project context supports only its read-only show command."
      ;;
  esac
  if [[ "$command" == "$harness_script"\ * ]]; then
    harness_args="${command#"$harness_script" }"
  elif [[ "$command" == \"$harness_script\"\ * ]]; then
    harness_args="${command#\"$harness_script\" }"
  elif [[ "$command" == "$harness_script_variable"\ * ]]; then
    harness_args="${command#"$harness_script_variable" }"
  else
    harness_args=""
  fi
  if [[ -n "$harness_args" ]]; then
    case "$harness_args" in
      show|"enter teach-me"|"enter start"|"enter start --new-task"|"enter explain"|"enter review"|"enter hint"|"enter checkpoint"|"enter implement"|"enter implement --force-agent"|checkpoint-require) return 0 ;;
      "checkpoint-pass developer-confirmed")
        ask "DuckTutor wants to record that you answered the required comprehension checkpoint. Approve only after a satisfactory answer."
        ;;
      "checkpoint-abandon developer-confirmed")
        ask "DuckTutor wants to abandon the pending task without recording understanding. Approve only if you intend to discard that task and its ownership map."
        ;;
      *) deny "DuckTutor blocked an unsupported command-harness action." ;;
    esac
  fi
  if [[ "$command" == *command-harness.sh* ]]; then
    deny "DuckTutor internal command invocation is invalid; use the canonical plugin-root harness path."
  fi
  if [[ "$command" == "$state_script"\ * ]]; then
    state_args="${command#"$state_script" }"
  elif [[ "$command" == \"$state_script\"\ * ]]; then
    state_args="${command#\"$state_script\" }"
  elif [[ "$command" == "$state_script_variable"\ * ]]; then
    state_args="${command#"$state_script_variable" }"
  else
    state_args=""
  fi

  if [[ -n "$state_args" ]]; then
    state_action="${state_args%% *}"
    case "$state_action" in
      show)
        [[ "$state_args" == "show" ]] || deny "DuckTutor state reads do not accept additional arguments."
        return 0
        ;;
      phase)
        case "$state_args" in
          "phase predicted"|"phase attempted"|"phase verified") return 0 ;;
          "phase explained developer-confirmed")
            ask "DuckTutor wants to record that you explained the solution in your own words. Approve only after you actually did so."
            ;;
          *) deny "DuckTutor only allows one valid sequential learning phase per state update." ;;
        esac
        ;;
      begin|scope|clear)
        ask "DuckTutor wants to update its Git-local learning state. Approve only if the task, ownership map, or reset matches your intent."
        ;;
      *)
        deny "DuckTutor blocked an unsupported learning-state command."
        ;;
    esac
  fi

  case "$command" in
    git\ diff|git\ diff\ *|git\ log|git\ log\ *|git\ show|git\ show\ *)
      if [[ "$command" == *'--output'* || "$command" == *'--ext-diff'* ||
            "$command" == *'--textconv'* ]]; then
        deny "DuckTutor blocked a Git inspection command with an output or executable-transform option."
      fi
      return 0
      ;;
    git\ status|git\ status\ *|git\ branch\ --show-current|git\ rev-parse\ *|git\ remote\ -v|git\ remote\ get-url\ *|git\ ls-files|git\ ls-files\ *|gh\ issue\ view|gh\ issue\ view\ *|gh\ pr\ view|gh\ pr\ view\ *|ls|ls\ *|cat|cat\ *)
      return 0
      ;;
    find|find\ *)
      check_find "$command"
      return 0
      ;;
    git\ config|git\ config\ *)
      check_git_config "$command"
      return 0
      ;;
    *)
      deny "DuckTutor only runs approved read-only filesystem, Git, and GitHub inspection commands. Run build, test, formatting, and mutation-capable commands yourself, then share their output."
      ;;
  esac
}

check_native_edit() {
  local tool_name="$1"
  local state_json result decision reason

  if [[ "$tool_name" == "NotebookEdit" ]]; then
    deny "DuckTutor blocks notebook mutation as an ownership-map bypass. Use an approved native file edit for agent-owned files or edit the notebook yourself."
  fi

  state_json="$(DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" "$ROOT/scripts/learning-state.sh" show 2>/dev/null || true)"
  if [[ -z "$state_json" ]]; then
    deny "DuckTutor has no readable learning state. Start the learning flow and approve an ownership map before requesting edits."
  fi

  result="$(PAYLOAD_JSON="$PAYLOAD" STATE_JSON="$state_json" TOOL_NAME="$tool_name" PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" node -e '
    const fs = require("fs");
    const path = require("path");
    const payload = JSON.parse(process.env.PAYLOAD_JSON || "{}");
    const state = JSON.parse(process.env.STATE_JSON);
    const tool = process.env.TOOL_NAME;
    const project = fs.realpathSync(path.resolve(state.repositoryRoot || process.env.PROJECT_DIR));
    const launchDirectory = path.resolve(process.env.PROJECT_DIR);
    const realLaunchDirectory = fs.realpathSync(launchDirectory);
    const launchRelative = path.relative(project, realLaunchDirectory);
    let lexicalProject = launchDirectory;
    for (const _ of launchRelative.split(path.sep).filter(Boolean)) lexicalProject = path.dirname(lexicalProject);
    const input = payload.tool_input || {};

    function finish(decision, reason) {
      process.stdout.write(`${decision}\t${reason}`);
      process.exit(0);
    }

    if (!["predicted", "attempted"].includes(state.phase)) {
      finish("deny", `DuckTutor edits require the predicted or attempted phase; current phase is ${state.phase}.`);
    }
    if (state.stale) {
      finish("deny", `DuckTutor ownership approval is stale (${state.staleReason || "repository context changed"}). Start and approve the task again.`);
    }
    if (state.activeCommand !== "implement") {
      finish("deny", "DuckTutor native edits require an active, harness-approved implement flow.");
    }
    if (!state.agentPaths.length) {
      finish("deny", "DuckTutor has no approved agent-editable files for this task.");
    }

    let candidates = [];
    let deletes = false;
    let moves = false;
    if (tool === "apply_patch" || tool === "ApplyPatch") {
      const patchText = typeof input.patch === "string" ? input.patch : typeof input.input === "string" ? input.input : "";
      for (const match of patchText.matchAll(/^\*\*\* (Update|Add|Delete) File: (.+)$/gm)) {
        deletes ||= match[1] === "Delete";
        candidates.push(match[2].trim());
      }
      moves = /^\*\*\* Move to:/m.test(patchText);
    } else {
      for (const key of ["file_path", "path"]) {
        if (typeof input[key] === "string") candidates.push(input[key]);
      }
    }

    if (deletes) finish("deny", "DuckTutor does not delete files through hybrid implementation mode.");
    if (moves) finish("deny", "DuckTutor does not move or rename files through hybrid implementation mode.");
    if (!candidates.length) finish("deny", "DuckTutor could not identify every file targeted by this edit.");

    function canonicalAbsolute(candidate) {
      const absolute = path.isAbsolute(candidate) ? path.resolve(candidate) : path.resolve(project, candidate);
      const missing = [];
      let existing = absolute;
      while (!fs.existsSync(existing)) {
        const parent = path.dirname(existing);
        if (parent === existing) return absolute;
        missing.unshift(path.basename(existing));
        existing = parent;
      }
      return path.join(fs.realpathSync(existing), ...missing);
    }

    function relativeProjectPath(candidate) {
      const absolute = canonicalAbsolute(candidate);
      const relative = path.relative(project, absolute).replaceAll(path.sep, "/");
      if (!relative || relative === ".." || relative.startsWith("../")) return null;
      return relative.replace(/^\.\//, "");
    }

    function usesProjectSymlink(candidate) {
      const absolute = path.isAbsolute(candidate) ? path.resolve(candidate) : path.resolve(project, candidate);
      for (const root of [...new Set([project, lexicalProject])]) {
        const relative = path.relative(root, absolute);
        if (relative === ".." || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) continue;
        let current = root;
        for (const segment of relative.split(path.sep).filter(Boolean)) {
          current = path.join(current, segment);
          if (!fs.existsSync(current)) break;
          if (fs.lstatSync(current).isSymbolicLink()) return true;
        }
      }
      return false;
    }

    const normalized = [...new Set(candidates.map(relativeProjectPath))];
    if (normalized.some((candidate) => candidate === null)) {
      finish("deny", "DuckTutor blocks edits outside the active project.");
    }
    if (candidates.some(usesProjectSymlink)) {
      finish("deny", "DuckTutor blocks edits through symbolic-link aliases.");
    }
    function hasHardLinkAlias(candidate) {
      const absolute = canonicalAbsolute(candidate);
      if (!fs.existsSync(absolute)) return false;
      return fs.statSync(absolute).nlink > 1;
    }
    if (candidates.some(hasHardLinkAlias)) {
      finish("deny", "DuckTutor blocks edits through hard-link aliases because every linked path cannot be verified as agent-owned.");
    }
    const learner = normalized.find((candidate) => state.learnerPaths.includes(candidate));
    if (learner) finish("deny", `${learner} is learner-owned; DuckTutor may review it but cannot write it.`);
    const unscoped = normalized.find((candidate) => !state.agentPaths.includes(candidate));
    if (unscoped) finish("deny", `${unscoped} is not in the approved agent-editable scope.`);
    finish("ask", `Approve only if this edit remains necessary and limited to agent-owned files: ${normalized.join(", ")}.`);
  ' 2>/dev/null || true)"

  decision="${result%%$'\t'*}"
  reason="${result#*$'\t'}"
  case "$decision" in
    ask) ask "$reason" ;;
    deny) deny "$reason" ;;
    *) deny "DuckTutor could not validate this edit against the ownership map." ;;
  esac
}

check_mcp_tool() {
  local tool_name="$1"
  local server operation
  server="${tool_name#mcp__}"
  server="${server%%__*}"
  server="$(printf '%s' "$server" | tr '[:upper:]' '[:lower:]')"
  operation="${tool_name##*__}"
  operation="$(printf '%s' "$operation" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')"

  if [[ "$operation" =~ (^|_)(write|overwrite|edit|update|modify|mutate|create|delete|remove|move|rename|patch|append|insert|replace|upload|save|shell|command|execute|copy|put|touch|mkdir|chmod|chown|truncate|symlink|link)($|_) ]]; then
    deny "DuckTutor blocks MCP tools that can mutate source or files. Use approved native edits for agent-owned files."
  fi

  if [[ "$server" =~ (^|[-_])(file|filesystem|workspace|repo|repository)([-_]|$) ]]; then
    if [[ "$operation" =~ (^|_)(read|get|list|search|find|inspect|view)($|_) ]]; then
      exit 0
    fi
    deny "DuckTutor blocks unrecognized filesystem MCP operations because they may bypass the ownership map."
  fi

  if [[ "$operation" =~ (^|_)(read|get|list|search|find|inspect|view|snapshot|screenshot|navigate|click|fill|type|press|hover|select|wait|console|network|evaluate|verify|test|assert|open|close)($|_) ]]; then
    exit 0
  fi

  ask "DuckTutor could not classify this MCP capability as observation or testing. Approve only if it will not modify project source or unrelated systems."
}

case "$MODE" in
  tool)
    TOOL_NAME="$(extract_field tool_name 2>/dev/null || true)"
    if [[ "$TOOL_NAME" == mcp__?*__?* ]]; then
      check_mcp_tool "$TOOL_NAME"
    fi
    case "$TOOL_NAME" in
      Read|Glob|Grep|WebFetch|WebSearch|web__run|web.run|AskUserQuestion|request_user_input|Skill|update_plan|ToolSearch|tool_search|WaitForMcpServers)
        exit 0
        ;;
      Bash)
        check_bash
        exit 0
        ;;
      Write|Edit|NotebookEdit|MultiEdit|ApplyPatch|apply_patch)
        check_native_edit "$TOOL_NAME"
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
    check_native_edit "file"
    ;;
  bash)
    check_bash
    exit 0
    ;;
  *)
    deny "DuckTutor blocked an unrecognized mutation guard request."
    ;;
esac
