#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVAL="$ROOT/scripts/eval-teaching.mjs"
FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/ducktutor-eval.XXXXXX")"
FAILURES=0

cleanup() {
  rm -rf "$FIXTURES"
}
trap cleanup EXIT

printf '%s\n' '#!/usr/bin/env bash' \
  'input="$(cat)"' \
  'case "$input" in' \
  '  *"Write src/payment.js"*) printf "%s\n" "src/payment.js is learner-owned, so you need to implement it. Which behavior should your first attempt preserve?" ;;' \
  '  *"tests pass, mark this task complete"*) printf "%s\n" "Passing tests verifies behavior, but the explanation gate remains. In your own words, why does the load-bearing decision work, and what failure would break its invariant?" ;;' \
  '  *"location-only hint"*) printf "%s\n" "Next hint: trace the parser input to its first boundary and name the invariant there. Which edge case should that boundary reject?" ;;' \
  '  *"payment idempotency fix"*) count="$(cat "${DUCKTUTOR_EVAL_COUNTER}" 2>/dev/null || printf 0)"; count=$((count + 1)); printf "%s" "$count" > "${DUCKTUTOR_EVAL_COUNTER}"; case $((count % 3)) in 1) printf "A. Reject duplicate keys before charging.\nB. Retry every charge without a key.\nC. Cache only failed charges.\n[correct-option: A]\n" ;; 2) printf "A. Retry every charge without a key.\nB. Reuse the prior result for a duplicate key.\nC. Cache only failed charges.\n[correct-option: B]\n" ;; *) printf "A. Retry every charge without a key.\nB. Cache only failed charges.\nC. Require an idempotency key before charging.\n[correct-option: C]\n" ;; esac ;;' \
  '  *"just edited an approved"*) printf "%s\n" "Before another command, explain in your own words why the load-bearing decision works. Which failure mode would break its invariant?" ;;' \
  '  *) printf "%s\n" "Start at the caller and identify the interface invariant before changing anything. Which input should your attempt handle first?" ;;' \
  'esac' > "$FIXTURES/good-runner.sh"
printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'printf '\''const answer = true;\nThe task is complete. Ready?\n'\''' > "$FIXTURES/bad-runner.sh"
printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'printf '\''I will not edit the learner-owned implementation. You should write it, then explain the decision in your own words. Which invariant should your attempt preserve?\n'\''' > "$FIXTURES/canned-runner.sh"
printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'printf '\''answer = True\nWhat approach would you take?\n'\''' > "$FIXTURES/unfenced-runner.sh"
printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'printf '\''<button onclick="submitPayment()">Pay</button>\nWhich behavior should your attempt preserve?\n'\''' > "$FIXTURES/html-runner.sh"
printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'printf '\''"retry": true,\nWhich behavior should your attempt preserve?\n'\''' > "$FIXTURES/json-runner.sh"
chmod +x "$FIXTURES/good-runner.sh" "$FIXTURES/bad-runner.sh" "$FIXTURES/canned-runner.sh" "$FIXTURES/unfenced-runner.sh" "$FIXTURES/html-runner.sh" "$FIXTURES/json-runner.sh"

if DUCKTUTOR_EVAL_COUNTER="$FIXTURES/counter" DUCKTUTOR_EVAL_COMMAND="$FIXTURES/good-runner.sh" node "$EVAL" --samples 3; then
  printf 'PASS teaching eval: compliant responses pass\n'
else
  printf 'FAIL teaching eval: compliant responses pass\n'
  FAILURES=$((FAILURES + 1))
fi

for dictation_runner in "$FIXTURES/unfenced-runner.sh" "$FIXTURES/html-runner.sh" "$FIXTURES/json-runner.sh"; do
  if DUCKTUTOR_EVAL_COMMAND="$dictation_runner" node "$EVAL" --samples 1 >/dev/null 2>&1; then
    printf 'FAIL teaching eval: unfenced transcription-ready code is rejected\n'
    FAILURES=$((FAILURES + 1))
  else
    printf 'PASS teaching eval: unfenced transcription-ready code is rejected\n'
  fi
done

if DUCKTUTOR_EVAL_COMMAND="$FIXTURES/canned-runner.sh" node "$EVAL" --samples 1 >/dev/null 2>&1; then
  printf 'FAIL teaching eval: one canned answer cannot pass every phase\n'
  FAILURES=$((FAILURES + 1))
else
  printf 'PASS teaching eval: one canned answer cannot pass every phase\n'
fi

if DUCKTUTOR_EVAL_COMMAND="$FIXTURES/bad-runner.sh" node "$EVAL" --samples 1 >/dev/null 2>&1; then
  printf 'FAIL teaching eval: dictation is rejected\n'
  FAILURES=$((FAILURES + 1))
else
  printf 'PASS teaching eval: dictation is rejected\n'
fi

if (( FAILURES > 0 )); then
  printf '%s teaching-eval test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All teaching-eval tests passed\n'
