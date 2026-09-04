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
    [[ "$#" -eq 1 || ( "$#" -eq 2 && "$2" == "deep-reflection" ) ]] || exit 1
    if [[ "$#" -eq 2 ]]; then
      DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" "$STATE" checkpoint require deep-reflection
    else
      DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" "$STATE" checkpoint require
    fi
    ;;
  checkpoint-pass)
    [[ "$#" -eq 2 && "$2" =~ ^(quiz-confirmed|free-text-confirmed)$ ]] || exit 1
    DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" "$STATE" checkpoint pass "$2"
    ;;
  checkpoint-record)
    [[ "$#" -eq 2 && "$2" =~ ^(correct|incorrect|unsure)$ ]] || exit 1
    DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" "$STATE" checkpoint record "$2"
    ;;
  checkpoint-abandon)
    [[ "$#" -eq 2 && "$2" == "choice-confirmed" ]] || exit 1
    DUCKTUTOR_PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}" "$STATE" checkpoint abandon choice-confirmed
    ;;
  *)
    printf 'DuckTutor harness: supported commands are show, enter, checkpoint-require [deep-reflection], checkpoint-record, checkpoint-pass, and checkpoint-abandon\n' >&2
    exit 1
    ;;
esac
