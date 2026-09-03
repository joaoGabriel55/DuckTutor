#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$ROOT/scripts/learning-state.sh"
COMMAND="${1:-show}"

case "$COMMAND" in
  show)
    [[ "$#" -eq 1 ]] || exit 1
    DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" "$STATE" show
    ;;
  enter)
    [[ "$#" -eq 2 || ( "$#" -eq 3 && "$2" == "implement" && "$3" == "--force-agent" ) || ( "$#" -eq 3 && "$2" == "start" && "$3" == "--new-task" ) ]] || exit 1
    DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" "$STATE" engage "${@:2}"
    ;;
  checkpoint-require)
    [[ "$#" -eq 1 ]] || exit 1
    DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" "$STATE" checkpoint require
    ;;
  checkpoint-pass)
    [[ "$#" -eq 2 && "$2" == "developer-confirmed" ]] || exit 1
    DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" "$STATE" checkpoint pass developer-confirmed
    ;;
  checkpoint-abandon)
    [[ "$#" -eq 2 && "$2" == "developer-confirmed" ]] || exit 1
    DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" "$STATE" checkpoint abandon developer-confirmed
    ;;
  *)
    printf 'DuckTutor harness: supported commands are show, enter, checkpoint-require, checkpoint-pass, and checkpoint-abandon\n' >&2
    exit 1
    ;;
esac
