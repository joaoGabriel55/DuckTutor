#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$ROOT/scripts/learning-state.sh"
PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}"

usage() {
  printf '%s\n' \
    'Usage:' \
    '  /ducktutor:clean' \
    '  /ducktutor:clean --help' \
    '' \
    'Remove all Git-local DuckTutor state for this repository.' \
    'This clears active tasks, checkpoints, history, and configuration; quiz mode becomes the default.' \
    'Project files and Git history are not changed.'
}

case "${1:-}" in
  "")
    [[ "$#" -eq 0 ]] || { usage >&2; exit 2; }
    DUCKTUTOR_PROJECT_DIR="$PROJECT_DIR" "$STATE" clean argument-confirmed >/dev/null
    printf 'DuckTutor state cleaned. Response mode reset to quiz.\n'
    ;;
  --help)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
