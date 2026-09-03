#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCHMARK="$ROOT/scripts/benchmark-tokens.mjs"
FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/ducktutor-benchmark.XXXXXX")"
FAILURES=0

cleanup() {
  rm -rf "$FIXTURES"
}
trap cleanup EXIT

printf '%s\n' '#!/usr/bin/env bash' \
  'input="$(cat)"' \
  'git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 7' \
  '[[ "$PWD" != "$DUCKTUTOR_BENCHMARK_TEST_ROOT" ]] || exit 8' \
  '[[ "$input" == *"Do not use tools or edit files"* ]] || exit 9' \
  'touch benchmark-side-effect' \
  'if [[ "$input" == *"# DuckTutor"* ]]; then' \
  '  printf DDDDDDDD' \
  'else' \
  '  printf BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' \
  'fi' > "$FIXTURES/runner.sh"
chmod +x "$FIXTURES/runner.sh"
printf '%s\n' '#!/usr/bin/env bash' \
  'cat >/dev/null' \
  'printf %s "$PWD" > "$DUCKTUTOR_FAILURE_PATH"' \
  'printf AUTH_REQUIRED' \
  'for ((index = 0; index < 2000; index += 1)); do printf x >&2; done' \
  'exit 11' > "$FIXTURES/failing-runner.sh"
chmod +x "$FIXTURES/failing-runner.sh"

if DUCKTUTOR_BENCHMARK_TEST_ROOT="$ROOT" DUCKTUTOR_BENCHMARK_LABEL="fixture-model deterministic" DUCKTUTOR_BENCHMARK_COMMAND="$FIXTURES/runner.sh" node "$BENCHMARK" --samples 2 > "$FIXTURES/output" 2> "$FIXTURES/error"; then
  output="$(cat "$FIXTURES/output")"
  if [[ "$output" == *'Configuration: fixture-model deterministic'* &&
        "$output" == *'Method: ceil(characters / 4); 5 scenarios; 2 samples each.'* &&
        "$output" == *'Model calls: 20 (10 baseline + 10 DuckTutor).'* &&
        "$output" == *'explain-approach'* &&
        "$output" == *'diff-proportionality'* &&
        "$output" == *'premature-abstraction'* &&
        "$output" == *'reasoning-coupling'* &&
        "$output" == *'understanding-over-output'* &&
        "$output" == *'Per-pair averages'* &&
        "$output" == *'DuckTutor prompt overhead'* &&
        "$output" == *'explain-approach | 10 | 2 | 8 (80.0%) | 75 | 996 | 921 | -913'* &&
        "$output" == *'Actual run totals'* &&
        "$output" == *'Aggregate | 100 | 20 | 80 (80.0%) | 750 | 9956 | 9206 | -9126'* &&
        ! -e "$ROOT/benchmark-side-effect" ]]; then
    printf 'PASS token benchmark: reports reproducible per-scenario and aggregate estimates\n'
  else
    printf 'FAIL token benchmark: reports reproducible per-scenario and aggregate estimates\n'
    FAILURES=$((FAILURES + 1))
  fi
else
  printf 'FAIL token benchmark: valid invocation succeeds\n'
  FAILURES=$((FAILURES + 1))
fi

if node "$BENCHMARK" --samples 2 > /dev/null 2> "$FIXTURES/missing-error"; then
  printf 'FAIL token benchmark: missing runner is rejected\n'
  FAILURES=$((FAILURES + 1))
elif grep -q 'DUCKTUTOR_BENCHMARK_COMMAND' "$FIXTURES/missing-error"; then
  printf 'PASS token benchmark: missing runner is rejected clearly\n'
else
  printf 'FAIL token benchmark: missing runner is rejected clearly\n'
  FAILURES=$((FAILURES + 1))
fi

if DUCKTUTOR_BENCHMARK_TEST_ROOT="$ROOT" DUCKTUTOR_BENCHMARK_COMMAND="$FIXTURES/runner.sh" node "$BENCHMARK" --samples 1 > /dev/null 2> "$FIXTURES/label-error"; then
  printf 'FAIL token benchmark: missing configuration label is rejected\n'
  FAILURES=$((FAILURES + 1))
elif grep -q 'DUCKTUTOR_BENCHMARK_LABEL' "$FIXTURES/label-error"; then
  printf 'PASS token benchmark: missing configuration label is rejected clearly\n'
else
  printf 'FAIL token benchmark: missing configuration label is rejected clearly\n'
  FAILURES=$((FAILURES + 1))
fi

if DUCKTUTOR_BENCHMARK_LABEL="missing alias" DUCKTUTOR_BENCHMARK_COMMAND="ducktutor_missing_shell_alias -p" node "$BENCHMARK" --samples 1 > /dev/null 2> "$FIXTURES/alias-error"; then
  printf 'FAIL token benchmark: unavailable shell alias is rejected\n'
  FAILURES=$((FAILURES + 1))
elif grep -q 'non-interactive /bin/sh' "$FIXTURES/alias-error" &&
     grep -q 'aliases and functions are unavailable' "$FIXTURES/alias-error" &&
     grep -q 'underlying executable' "$FIXTURES/alias-error"; then
  printf 'PASS token benchmark: unavailable shell alias has actionable guidance\n'
else
  printf 'FAIL token benchmark: unavailable shell alias has actionable guidance\n'
  FAILURES=$((FAILURES + 1))
fi

if DUCKTUTOR_FAILURE_PATH="$FIXTURES/failure-workspace" DUCKTUTOR_BENCHMARK_LABEL="fixture failure" DUCKTUTOR_BENCHMARK_COMMAND="$FIXTURES/failing-runner.sh" node "$BENCHMARK" --samples 1 > /dev/null 2> "$FIXTURES/failure-error"; then
  printf 'FAIL token benchmark: runner failure is propagated\n'
  FAILURES=$((FAILURES + 1))
else
  failed_workspace="$(cat "$FIXTURES/failure-workspace")"
  failure_error_size="$(wc -c < "$FIXTURES/failure-error")"
  if [[ -n "$failed_workspace" && ! -d "$failed_workspace" &&
        "$failure_error_size" -le 1200 ]] &&
     grep -q '^Error: explain-approach baseline sample 1 failed with exit 11' "$FIXTURES/failure-error" &&
     grep -q 'stdout: AUTH_REQUIRED' "$FIXTURES/failure-error" &&
     grep -q 'stderr: xxx' "$FIXTURES/failure-error" &&
     ! grep -q ' at run ' "$FIXTURES/failure-error"; then
    printf 'PASS token benchmark: failed runs clean up and bound diagnostics\n'
  else
    printf 'FAIL token benchmark: failed runs clean up and bound diagnostics\n'
    FAILURES=$((FAILURES + 1))
  fi
fi

if grep -q '^## Approximate token benchmark$' "$ROOT/README.md" &&
   grep -q 'output savings' "$ROOT/README.md" &&
   grep -q 'net savings' "$ROOT/README.md" &&
   grep -q 'benchmark-tokens.mjs --samples 3' "$ROOT/README.md" &&
   grep -q 'aliases and functions' "$ROOT/README.md" &&
   grep -q 'prompt overhead' "$ROOT/README.md" &&
   grep -q '^### Historical results — 2026-09-03 (v0.10.0, pre-optimization)$' "$ROOT/README.md" &&
   grep -q 'non-reproducible' "$ROOT/README.md" &&
   grep -q '^### Codex prompt optimization in v0.11.0$' "$ROOT/README.md" &&
   grep -q '^#### Codex Sol$' "$ROOT/README.md" &&
   grep -q '^#### Claude Opus 5$' "$ROOT/README.md" &&
   grep -q 'docs/benchmark-output-comparison.svg' "$ROOT/README.md" &&
   grep -q 'Codex Sol baseline' "$ROOT/docs/benchmark-output-comparison.svg" &&
   grep -q 'Claude Opus 5 DuckTutor' "$ROOT/docs/benchmark-output-comparison.svg" &&
   grep -q 'color-scheme: light dark' "$ROOT/docs/benchmark-output-comparison.svg" &&
   grep -q '\.background { fill: #ffffff; }' "$ROOT/docs/benchmark-output-comparison.svg" &&
   grep -q '@media (prefers-color-scheme: dark)' "$ROOT/docs/benchmark-output-comparison.svg" &&
   grep -q '\.background { fill: #0d1117; }' "$ROOT/docs/benchmark-output-comparison.svg" &&
   grep -q '\.baseline { stroke: #d29922; }' "$ROOT/docs/benchmark-output-comparison.svg" &&
   grep -q '\.ducktutor { stroke: #58a6ff; }' "$ROOT/docs/benchmark-output-comparison.svg" &&
   grep -q '| Aggregate (total) | 11854 | 6609 | 5245 (44.2%) | -13910 |' "$ROOT/README.md" &&
   grep -qi 'model-call cost' "$ROOT/CONTRIBUTING.md"; then
  printf 'PASS token benchmark: user and contributor documentation disclose the trade-off\n'
else
  printf 'FAIL token benchmark: user and contributor documentation disclose the trade-off\n'
  FAILURES=$((FAILURES + 1))
fi

if (( FAILURES > 0 )); then
  printf '%s token benchmark test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All token benchmark tests passed\n'
