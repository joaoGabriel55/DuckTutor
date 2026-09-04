#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT/hooks/guard.sh"
STATE="$ROOT/scripts/learning-state.sh"
PROJECT_CONTEXT="$ROOT/scripts/project-context.sh"
HARNESS="$ROOT/scripts/command-harness.sh"
PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/ducktutor-guard.XXXXXX")"
OUTSIDE="$(mktemp -d "${TMPDIR:-/tmp}/ducktutor-outside.XXXXXX")"
FAILURES=0

cleanup() {
  rm -rf "$PROJECT"
  rm -rf "$OUTSIDE"
}
trap cleanup EXIT

git -C "$PROJECT" init -q
git -C "$PROJECT" config user.name "DuckTutor Test"
git -C "$PROJECT" config user.email "test@ducktutor.invalid"
git -C "$PROJECT" commit --allow-empty -qm "initial"
mkdir -p "$PROJECT/src" "$PROJECT/test" "$PROJECT/docs"
printf 'source\n' > "$PROJECT/src/app.js"
printf 'secret\n' > "$PROJECT/src/secret.js"
ln -s ../src/app.js "$PROJECT/test/app-link.js"
ln "$PROJECT/src/app.js" "$PROJECT/test/app-hard.js"
ln "$PROJECT/src/secret.js" "$PROJECT/test/unscoped-hard.js"
ln -s "$OUTSIDE" "$PROJECT/linked"
ln -s "$PROJECT" "$OUTSIDE/project-alias"

guard() {
  DUCKTUTOR_PROJECT_DIR="$PROJECT" "$GUARD" "$@"
}

expect_allowed() {
  local name="$1"
  local command="$2"
  local payload output
  payload="$(COMMAND="$command" node -e 'process.stdout.write(JSON.stringify({tool_input:{command:process.env.COMMAND}}))')"
  output="$(printf '%s' "$payload" | guard bash)"
  if [[ -n "$output" ]]; then
    printf 'FAIL allowed: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  else
    printf 'PASS allowed: %s\n' "$name"
  fi
}

expect_denied() {
  local name="$1"
  local command="$2"
  local payload output
  payload="$(COMMAND="$command" node -e 'process.stdout.write(JSON.stringify({tool_input:{command:process.env.COMMAND}}))')"
  output="$(printf '%s' "$payload" | guard bash)"
  if [[ "$output" == *'"permissionDecision":"deny"'* ]]; then
    printf 'PASS denied: %s\n' "$name"
  else
    printf 'FAIL denied: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_allowed "working tree status" "git status --short"
expect_allowed "unstaged diff" "git diff"
expect_allowed "staged diff" "git diff --staged"
expect_allowed "commit context" "git log --oneline -5"
expect_allowed "tracked content search" 'git grep -n "DropdownComponent.new" -- app/views app/components'
expect_allowed "issue inspection" "gh issue view 42 --comments"
expect_allowed "pull request inspection" "gh pr view 42 --comments"
expect_allowed "directory listing" "ls -la skills"
expect_allowed "file contents" "cat README.md"
expect_allowed "file search" "find skills -name SKILL.md"
expect_allowed "Git config list" "git config --list --show-origin"
expect_allowed "Git config scoped lookup" "git config --global --get user.name"
expect_allowed "Git config direct lookup" "git config user.name"

expect_denied "test execution" "npm test"
expect_denied "shell redirection" "printf changed > src/app.js"
expect_denied "compound bypass" "git status && rm source.rb"
expect_denied "patch application" "git apply change.patch"
expect_denied "Git output file" "git diff --output=change.patch"
expect_denied "lookalike Git subcommand" "git diff-and-rewrite"
expect_denied "scripted rewrite" "python3 rewrite.py"
expect_denied "find deletion" "find . -delete"
expect_denied "find command execution" "find . -exec rm {} +"
expect_denied "find escaped command execution" "find . -\\exec rm {} +"
expect_denied "find file output" "find . -fprint results.txt"
expect_denied "Git config value set" "git config user.name DuckTutor"
expect_denied "global Git config value set" "git config --global user.email tutor@example.com"
expect_denied "Git config unset" "git config --unset user.name"
expect_denied "Git config set action" "git config set user.name DuckTutor"
expect_denied "Git config editor" "git config --edit"
expect_denied "Git grep text conversion" "git grep --textconv password"
expect_denied "Git grep external process" "git grep --ext-grep password"
expect_denied "Git grep pager process" "git grep -O less password"

expect_command_asked() {
  local name="$1"
  local command="$2"
  local payload output
  payload="$(COMMAND="$command" node -e 'process.stdout.write(JSON.stringify({tool_input:{command:process.env.COMMAND}}))')"
  output="$(printf '%s' "$payload" | guard bash)"
  if [[ "$output" == *'"permissionDecision":"ask"'* ]]; then
    printf 'PASS asked command: %s\n' "$name"
  else
    printf 'FAIL asked command: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_allowed "learning state read" "$STATE show"
expect_allowed "learning state read through plugin variable" '"${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" show'
expect_allowed "project context inventory" "$PROJECT_CONTEXT show"
expect_allowed "project context inventory through plugin variable" '"${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh" show'
expect_denied "unsupported project context command" "$PROJECT_CONTEXT scan"
expect_allowed "command harness state read" "$HARNESS show"
expect_allowed "command harness entry" "$HARNESS enter explain"
expect_allowed "command harness new-task entry" "$HARNESS enter start --new-task"
expect_allowed "plugin-variable new-task entry" '"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" enter start --new-task'
expect_denied "explain cannot create task state" "$HARNESS enter explain --new-task"
expect_allowed "command harness forced implementation entry" "$HARNESS enter implement --force-agent"
expect_denied "unknown command harness implementation flag" "$HARNESS enter implement --force"
expect_denied "unknown command harness checkpoint flag" "$HARNESS enter checkpoint --verbose"
expect_allowed "command harness checkpoint requirement" "$HARNESS checkpoint-require"
expect_allowed "command harness deep-reflection requirement" "$HARNESS checkpoint-require deep-reflection"
expect_allowed "command harness records correct quiz choice" "$HARNESS checkpoint-record correct"
expect_allowed "command harness records unsure quiz choice" "$HARNESS checkpoint-record unsure"
expect_denied "command harness rejects unknown quiz result" "$HARNESS checkpoint-record guessed"
expect_command_asked "confirmed checkpoint completion" "$HARNESS checkpoint-pass quiz-confirmed"
expect_command_asked "confirmed free-text checkpoint completion" "$HARNESS checkpoint-pass free-text-confirmed"
expect_command_asked "confirmed checkpoint abandonment" "$HARNESS checkpoint-abandon choice-confirmed"
expect_denied "unconfirmed checkpoint abandonment" "$HARNESS checkpoint-abandon"
expect_denied "unsupported command harness action" "$HARNESS bypass"

bare_harness_payload='{"tool_input":{"command":"command-harness.sh enter explain"}}'
bare_harness_output="$(printf '%s' "$bare_harness_payload" | guard bash)"
if [[ "$bare_harness_output" == *'DuckTutor internal command invocation is invalid'* ]]; then
  printf 'PASS denied: bare internal harness gets a specific error\n'
else
  printf 'FAIL denied: bare internal harness gets a specific error\n'
  FAILURES=$((FAILURES + 1))
fi
expect_command_asked "learning task begin" "$STATE begin guard-test"
expect_command_asked "ownership map change" "$STATE scope learner:src/app.js agent:test/app.test.js"
expect_allowed "learning phase advance" "$STATE phase attempted"
expect_denied "unconfirmed assessment phase" "$STATE phase assessed"
expect_command_asked "confirmed assessment phase" "$STATE phase assessed assessment-confirmed"
expect_command_asked "learning state clear" "$STATE clear"

unscoped_payload='{"tool_name":"Edit","tool_input":{"file_path":"src/app.js","old_string":"a","new_string":"b"}}'
unscoped_output="$(printf '%s' "$unscoped_payload" | guard tool)"
if [[ "$unscoped_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: edit without learning state\n'
else
  printf 'FAIL denied: edit without learning state\n'
  FAILURES=$((FAILURES + 1))
fi

DUCKTUTOR_PROJECT_DIR="$PROJECT" "$HARNESS" enter start >/dev/null
DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" begin "guard ownership test" >/dev/null
DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" phase predicted >/dev/null
DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" scope learner:src/app.js agent:test/app.test.js agent:test/app-link.js agent:test/app-hard.js agent:test/unscoped-hard.js agent:docs/app.md agent:linked/outside.txt >/dev/null

file_payload='{"tool_input":{"file_path":"test/app.test.js","content":"replacement"}}'
file_output="$(printf '%s' "$file_payload" | guard file)"
if [[ "$file_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: edit outside active implement flow\n'
else
  printf 'FAIL denied: edit outside active implement flow\n'
  FAILURES=$((FAILURES + 1))
fi

DUCKTUTOR_PROJECT_DIR="$PROJECT" "$HARNESS" enter implement >/dev/null
file_output="$(printf '%s' "$file_payload" | guard file)"
if [[ "$file_output" == *'"permissionDecision":"ask"'* ]]; then
    printf 'PASS asked: agent-owned file mutation\n'
else
    printf 'FAIL asked: agent-owned file mutation\n'
  FAILURES=$((FAILURES + 1))
fi

subdirectory_output="$(printf '%s' "$file_payload" | DUCKTUTOR_PROJECT_DIR="$PROJECT/test" "$GUARD" file)"
if [[ "$subdirectory_output" == *'"permissionDecision":"ask"'* ]]; then
  printf 'PASS asked: ownership paths stay repository-relative from subdirectories\n'
else
  printf 'FAIL asked: ownership paths stay repository-relative from subdirectories\n'
  FAILURES=$((FAILURES + 1))
fi

alias_root_payload="$(FILE_PATH="$OUTSIDE/project-alias/test/app.test.js" node -e 'process.stdout.write(JSON.stringify({tool_input:{file_path:process.env.FILE_PATH,content:"replacement"}}))')"
alias_root_output="$(printf '%s' "$alias_root_payload" | guard file)"
if [[ "$alias_root_output" == *'"permissionDecision":"ask"'* ]]; then
  printf 'PASS asked: canonical repository alias preserves approved ownership\n'
else
  printf 'FAIL asked: canonical repository alias preserves approved ownership\n'
  FAILURES=$((FAILURES + 1))
fi

expect_tool_allowed() {
  local name="$1"
  local tool_name="$2"
  local payload output
  payload="$(TOOL_NAME="$tool_name" node -e 'process.stdout.write(JSON.stringify({tool_name:process.env.TOOL_NAME,tool_input:{}}))')"
  output="$(printf '%s' "$payload" | guard tool)"
  if [[ -n "$output" ]]; then
    printf 'FAIL tool allowed: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  else
    printf 'PASS tool allowed: %s\n' "$name"
  fi
}

expect_tool_deferred_to_host() {
  local name="$1"
  local tool_name="$2"
  local payload output
  payload="$(TOOL_NAME="$tool_name" node -e 'process.stdout.write(JSON.stringify({tool_name:process.env.TOOL_NAME,tool_input:{}}))')"
  output="$(printf '%s' "$payload" | guard tool)"
  if [[ -z "$output" ]]; then
    printf 'PASS deferred to host: %s\n' "$name"
  else
    printf 'FAIL deferred to host: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_tool_denied() {
  local name="$1"
  local tool_name="$2"
  local payload output
  payload="$(TOOL_NAME="$tool_name" node -e 'process.stdout.write(JSON.stringify({tool_name:process.env.TOOL_NAME,tool_input:{}}))')"
  output="$(printf '%s' "$payload" | guard tool)"
  if [[ "$output" == *'"permissionDecision":"deny"'* ]]; then
    printf 'PASS tool denied: %s\n' "$name"
  else
    printf 'FAIL tool denied: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_tool_allowed "repository read" "Read"
expect_tool_allowed "Claude web fetch" "WebFetch"
expect_tool_allowed "Claude web search" "WebSearch"
expect_tool_allowed "Codex web research" "web__run"
expect_tool_allowed "comprehension question" "AskUserQuestion"
expect_tool_allowed "Codex comprehension question" "request_user_input"
expect_tool_allowed "Codex learning plan" "update_plan"
expect_tool_allowed "central tutor skill" "Skill"
expect_tool_allowed "Claude MCP tool discovery" "ToolSearch"
expect_tool_allowed "Codex MCP tool discovery" "tool_search"
expect_tool_allowed "Claude MCP connection wait" "WaitForMcpServers"
expect_tool_deferred_to_host "Playwright browser tool" "mcp__playwright__browser_navigate"
expect_tool_deferred_to_host "Chrome DevTools browser tool" "mcp__chrome_devtools__take_snapshot"
expect_tool_deferred_to_host "arbitrary host-configured MCP tool" "mcp__custom_qa__verify_feature"
expect_tool_denied "MCP filesystem write" "mcp__filesystem__write_file"
expect_tool_denied "MCP camelCase filesystem write" "mcp__filesystem__writeFile"
expect_tool_denied "MCP put file" "mcp__filesystem__put_file"
expect_tool_denied "MCP copy file" "mcp__filesystem__copy_file"
expect_tool_denied "MCP touch file" "mcp__filesystem__touch"
expect_tool_denied "MCP make directory" "mcp__filesystem__mkdir"
expect_tool_denied "MCP permission mutation" "mcp__filesystem__chmod"
expect_tool_denied "MCP generic source update" "mcp__custom__update_source"
expect_tool_denied "MCP generic file modification" "mcp__custom__modify_file"
expect_tool_denied "MCP generic overwrite" "mcp__custom__overwrite_asset"
expect_tool_deferred_to_host "MCP filesystem read" "mcp__filesystem__read_file"
expect_tool_deferred_to_host "MCP workspace listing" "mcp__workspace__list_files"
expect_tool_denied "MCP filesystem evaluator" "mcp__filesystem__evaluate"
expect_tool_denied "MCP workspace open" "mcp__workspace__open"
expect_tool_denied "MCP repository click" "mcp__repo__click"
expect_tool_denied "delegated bypass" "Agent"
expect_tool_denied "incomplete MCP name" "mcp__playwright"
expect_tool_denied "MCP name with empty server" "mcp____browser_navigate"
expect_tool_denied "MCP name with empty tool" "mcp__playwright__"
expect_tool_denied "unqualified browser tool" "browser_navigate"
expect_tool_denied "unknown future tool" "FutureMutationTool"

expect_tool_asked() {
  local name="$1"
  local tool_name="$2"
  local payload output
  local file_path="${3:-test/app.test.js}"
  payload="$(TOOL_NAME="$tool_name" FILE_PATH="$file_path" node -e 'process.stdout.write(JSON.stringify({tool_name:process.env.TOOL_NAME,tool_input:{file_path:process.env.FILE_PATH}}))')"
  output="$(printf '%s' "$payload" | guard tool)"
  if [[ "$output" == *'"permissionDecision":"ask"'* ]]; then
    printf 'PASS asked: %s\n' "$name"
  else
    printf 'FAIL asked: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_tool_asked "Claude agent-owned edit" "Edit"
expect_tool_asked "Claude agent-owned write" "Write"

learner_payload='{"tool_name":"Edit","tool_input":{"file_path":"src/app.js","old_string":"a","new_string":"b"}}'
learner_output="$(printf '%s' "$learner_payload" | guard tool)"
if [[ "$learner_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: learner-owned edit\n'
else
  printf 'FAIL denied: learner-owned edit\n'
  FAILURES=$((FAILURES + 1))
fi

outside_payload='{"tool_name":"Write","tool_input":{"file_path":"src/unscoped.js","content":"replacement"}}'
outside_output="$(printf '%s' "$outside_payload" | guard tool)"
if [[ "$outside_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: unscoped edit\n'
else
  printf 'FAIL denied: unscoped edit\n'
  FAILURES=$((FAILURES + 1))
fi

symlink_payload='{"tool_name":"Write","tool_input":{"file_path":"linked/outside.txt","content":"replacement"}}'
symlink_output="$(printf '%s' "$symlink_payload" | guard tool)"
if [[ "$symlink_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: symlink escape\n'
else
  printf 'FAIL denied: symlink escape\n'
  FAILURES=$((FAILURES + 1))
fi

alias_payload='{"tool_name":"Write","tool_input":{"file_path":"test/app-link.js","content":"replacement"}}'
alias_output="$(printf '%s' "$alias_payload" | guard tool)"
if [[ "$alias_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: in-project symlink ownership alias\n'
else
  printf 'FAIL denied: in-project symlink ownership alias\n'
  FAILURES=$((FAILURES + 1))
fi

hardlink_payload='{"tool_name":"Write","tool_input":{"file_path":"test/app-hard.js","content":"replacement"}}'
hardlink_output="$(printf '%s' "$hardlink_payload" | guard tool)"
if [[ "$hardlink_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: hard-link ownership alias\n'
else
  printf 'FAIL denied: hard-link ownership alias\n'
  FAILURES=$((FAILURES + 1))
fi

unscoped_hardlink_payload='{"tool_name":"Write","tool_input":{"file_path":"test/unscoped-hard.js","content":"replacement"}}'
unscoped_hardlink_output="$(printf '%s' "$unscoped_hardlink_payload" | guard tool)"
if [[ "$unscoped_hardlink_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: unscoped hard-link ownership alias\n'
else
  printf 'FAIL denied: unscoped hard-link ownership alias\n'
  FAILURES=$((FAILURES + 1))
fi

notebook_payload='{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"test/app.ipynb"}}'
notebook_output="$(printf '%s' "$notebook_payload" | guard tool)"
if [[ "$notebook_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: notebook mutation bypass\n'
else
  printf 'FAIL denied: notebook mutation bypass\n'
  FAILURES=$((FAILURES + 1))
fi

agent_patch='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: test/app.test.js\n@@\n-old\n+new\n*** End Patch"}}'
agent_patch_output="$(printf '%s' "$agent_patch" | guard tool)"
if [[ "$agent_patch_output" == *'"permissionDecision":"ask"'* ]]; then
  printf 'PASS asked: agent-owned patch\n'
else
  printf 'FAIL asked: agent-owned patch\n'
  FAILURES=$((FAILURES + 1))
fi

mixed_patch='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: test/app.test.js\n@@\n-old\n+new\n*** Update File: src/app.js\n@@\n-old\n+new\n*** End Patch"}}'
mixed_patch_output="$(printf '%s' "$mixed_patch" | guard tool)"
if [[ "$mixed_patch_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: patch crosses ownership map\n'
else
  printf 'FAIL denied: patch crosses ownership map\n'
  FAILURES=$((FAILURES + 1))
fi

delete_patch='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Delete File: test/app.test.js\n*** End Patch"}}'
delete_patch_output="$(printf '%s' "$delete_patch" | guard tool)"
if [[ "$delete_patch_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: patch deletion\n'
else
  printf 'FAIL denied: patch deletion\n'
  FAILURES=$((FAILURES + 1))
fi

move_patch='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: test/app.test.js\n*** Move to: src/app.js\n@@\n-old\n+new\n*** End Patch"}}'
move_patch_output="$(printf '%s' "$move_patch" | guard tool)"
if [[ "$move_patch_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: patch move bypass\n'
else
  printf 'FAIL denied: patch move bypass\n'
  FAILURES=$((FAILURES + 1))
fi

DUCKTUTOR_PROJECT_DIR="$PROJECT" "$HARNESS" enter implement --force-agent >/dev/null
DUCKTUTOR_PROJECT_DIR="$PROJECT" "$STATE" scope agent:docs/forced.js agent:test/app.test.js >/dev/null
force_agent_payload='{"tool_name":"Write","tool_input":{"file_path":"docs/forced.js","content":"replacement"}}'
force_agent_output="$(printf '%s' "$force_agent_payload" | guard tool)"
if [[ "$force_agent_output" == *'"permissionDecision":"ask"'* ]]; then
  printf 'PASS asked: force-agent mode edits an explicitly remapped source file\n'
else
  printf 'FAIL asked: force-agent mode edits an explicitly remapped source file\n'
  FAILURES=$((FAILURES + 1))
fi

force_unscoped_output="$(printf '%s' "$outside_payload" | guard tool)"
if [[ "$force_unscoped_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: force-agent mode cannot edit unscoped files\n'
else
  printf 'FAIL denied: force-agent mode cannot edit unscoped files\n'
  FAILURES=$((FAILURES + 1))
fi

git -C "$PROJECT" checkout -qb other-branch
stale_payload='{"tool_name":"Edit","tool_input":{"file_path":"test/app.test.js","old_string":"a","new_string":"b"}}'
stale_output="$(printf '%s' "$stale_payload" | guard tool)"
if [[ "$stale_output" == *'"permissionDecision":"deny"'* ]]; then
  printf 'PASS denied: stale ownership map\n'
else
  printf 'FAIL denied: stale ownership map\n'
  FAILURES=$((FAILURES + 1))
fi

if (( FAILURES > 0 )); then
  printf '%s guard test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All guard tests passed\n'
