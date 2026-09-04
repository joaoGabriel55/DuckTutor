#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$ROOT/scripts/learning-state.sh"
PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}"

usage() {
  printf '%s\n' \
    'Usage:' \
    '  /ducktutor:config --mode=quiz' \
    '  /ducktutor:config --mode=free-text' \
    '  /ducktutor:config --help' \
    '' \
    'Modes:' \
    '  quiz       Default. Ask single- or multi-select questions; checkpoints require two correct answers within three.' \
    '  free-text  Ask concise open-ended questions; checkpoints require a satisfactory explanation.' \
    '' \
    'Risk rule: force-agent work, scope growth, disproportionate diffs, and hidden coupling require deep reflection even in quiz mode.'
}

case "${1:-}" in
  --mode=quiz)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    DUCKTUTOR_PROJECT_DIR="$PROJECT_DIR" "$STATE" config set quiz argument-confirmed >/dev/null
    printf 'DuckTutor response mode set to quiz.\n'
    ;;
  --mode=free-text)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    DUCKTUTOR_PROJECT_DIR="$PROJECT_DIR" "$STATE" config set free-text argument-confirmed >/dev/null
    printf 'DuckTutor response mode set to free-text.\n'
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
