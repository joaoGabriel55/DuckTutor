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

expect_denied "test execution" "npm test"
expect_denied "shell redirection" "printf changed > src/app.js"
expect_denied "compound bypass" "git status && rm source.rb"
expect_denied "patch application" "git apply change.patch"
expect_denied "Git output file" "git diff --output=change.patch"
expect_denied "lookalike Git subcommand" "git diff-and-rewrite"
expect_denied "scripted rewrite" "python3 rewrite.py"

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
expect_tool_denied "delegated bypass" "Agent"
expect_tool_denied "external MCP bypass" "mcp__filesystem__write_file"
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
