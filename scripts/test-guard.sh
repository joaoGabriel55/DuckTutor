#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT/hooks/guard.sh"
FAILURES=0

expect_allowed() {
  local name="$1"
  local command="$2"
  local payload output
  payload="$(COMMAND="$command" node -e 'process.stdout.write(JSON.stringify({tool_input:{command:process.env.COMMAND}}))')"
  output="$(printf '%s' "$payload" | "$GUARD" bash)"
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
  output="$(printf '%s' "$payload" | "$GUARD" bash)"
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

file_payload='{"tool_input":{"file_path":"src/app.js","content":"replacement"}}'
file_output="$(printf '%s' "$file_payload" | "$GUARD" file)"
if [[ "$file_output" == *'"permissionDecision":"ask"'* ]]; then
  printf 'PASS asked: file mutation tool\n'
else
  printf 'FAIL asked: file mutation tool\n'
  FAILURES=$((FAILURES + 1))
fi

expect_tool_allowed() {
  local name="$1"
  local tool_name="$2"
  local payload output
  payload="$(TOOL_NAME="$tool_name" node -e 'process.stdout.write(JSON.stringify({tool_name:process.env.TOOL_NAME,tool_input:{}}))')"
  output="$(printf '%s' "$payload" | "$GUARD" tool)"
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
  output="$(printf '%s' "$payload" | "$GUARD" tool)"
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
  output="$(printf '%s' "$payload" | "$GUARD" tool)"
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
  payload="$(TOOL_NAME="$tool_name" node -e 'process.stdout.write(JSON.stringify({tool_name:process.env.TOOL_NAME,tool_input:{file_path:"src/app.js"}}))')"
  output="$(printf '%s' "$payload" | "$GUARD" tool)"
  if [[ "$output" == *'"permissionDecision":"ask"'* ]]; then
    printf 'PASS asked: %s\n' "$name"
  else
    printf 'FAIL asked: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_tool_asked "Claude direct edit" "Edit"
expect_tool_asked "Codex patch edit" "apply_patch"

if (( FAILURES > 0 )); then
  printf '%s guard test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All guard tests passed\n'
