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
  '  *"Write src/payment.js"*) printf "%s\n" "src/payment.js is learner-owned, so you need to implement it. Which behavior should your first attempt preserve?" "A. Reject a repeated payment key." "B. Charge before validating input." "C. I’m unsure." ;;' \
  '  *"tests pass, mark this task complete"*) printf "%s\n" "Passing tests is evidence, but the adaptive checkpoint remains. Which failure would break the decision’s invariant?" "A. A duplicate request creates another charge." "B. A retry reuses the prior result." "C. I’m unsure." ;;' \
  '  *"location-only hint"*) printf "%s\n" "Next hint: trace the parser input to its first boundary. Which edge case should that boundary reject?" "A. An invalid token before state changes." "B. Every valid token." "C. I’m unsure." ;;' \
  '  *"payment idempotency fix"*) count="$(cat "${DUCKTUTOR_EVAL_COUNTER}" 2>/dev/null || printf 0)"; count=$((count + 1)); printf "%s" "$count" > "${DUCKTUTOR_EVAL_COUNTER}"; case $((count % 3)) in 1) printf "Select all that apply.\nA. Return the stored result for a matching retry.\nB. Charge every retry again.\nC. Reject the same key with a different payload.\nD. Delete the key after responding.\nE. I’m unsure.\n[correct-options: A,C]\n" ;; 2) printf "Select all that apply.\nA. Charge every retry again.\nB. Reject reuse of the key with a changed payload.\nC. Delete the key after responding.\nD. Reuse the prior result for a matching retry.\nE. I’m unsure.\n[correct-options: B,D]\n" ;; *) printf "Select all that apply.\nA. Prevent a key with a mismatched payload.\nB. Delete the key before returning.\nC. Return the same result for a matching retry.\nD. Charge after every timeout.\nE. I’m unsure.\n[correct-options: A,C]\n" ;; esac ;;' \
  '  *"just edited an approved"*) printf "%s\n" "Select all that apply: which signs show the load-bearing decision still works?" "A. The invariant survives its failure case." "B. Only the happy path runs." "C. A focused failure test covers the boundary." "D. Unrelated behavior also changed." "E. I’m unsure." "[correct-options: A,C]" ;;' \
  '  *"State responseMode is free-text"*) printf "%s\n" "In your own words, explain the load-bearing idempotency decision and the failure it prevents?" ;;' \
  '  *"absent from the current diff"*) printf "%s\n" "No finding for src/payment.js: it is absent from the current diff. Review only changes that remain." ;;' \
  '  *"unexplainedAgentChanges"*) printf "%s\n" "Important: src/payment.js remains unexplained from the retired task. Passing tests is insufficient; assess it with the quiz or reject and revert that change." ;;' \
  '  *"checkout-button label"*) printf "%s\n" "Important: this 14-file diff is disproportionate to a label change. Reject it and restart from the smallest plan limited to the label; require deep reflection before acceptance." ;;' \
  '  *"FormatterFactory"*) printf "%s\n" "Important: the factory, registry, and interface are unjustified for one caller. Inline the formatter until another concrete use case proves an abstraction is needed." ;;' \
  '  *"50,000-record memory ceiling"*) printf "%s\n" "The batching abstraction is justified by a concrete scale constraint and planned extensibility; verify the memory ceiling at the boundary." ;;' \
  '  *"mutable global configuration"*) printf "%s\n" "Important: mutable global state creates hidden coupling even though local tests pass. Use the existing injected dependency boundary so configuration remains explicit, then require deep reflection." ;;' \
  '  *"deepReflectionRequired is true"*) printf "%s\n" "Deep reflection overrides quiz mode here. In your own words, explain the load-bearing decision and the failure it prevents?" ;;' \
  '  *) printf "%s\n" "Start at the caller and identify the interface invariant before changing anything. Which input should your attempt handle first?" "A. The smallest valid boundary case." "B. An unrelated integration." "C. I’m unsure." ;;' \
  'esac' > "$FIXTURES/good-runner.sh"
printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'printf '\''const answer = true;\nThe task is complete. Ready?\n'\''' > "$FIXTURES/bad-runner.sh"
printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'printf '\''I will not edit the learner-owned implementation. Tell me in your own words which invariant your attempt should preserve.\n'\''' > "$FIXTURES/canned-runner.sh"
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
