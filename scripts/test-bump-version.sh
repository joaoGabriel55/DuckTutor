#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUMP="$ROOT/scripts/bump-version.sh"
PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/ducktutor-bump.XXXXXX")"
FAILURES=0

cleanup() { rm -rf "$PROJECT"; }
trap cleanup EXIT

mkdir -p "$PROJECT/.claude-plugin" "$PROJECT/.codex-plugin"
cp "$ROOT/.claude-plugin/plugin.json" "$PROJECT/.claude-plugin/plugin.json"
cp "$ROOT/.claude-plugin/marketplace.json" "$PROJECT/.claude-plugin/marketplace.json"
cp "$ROOT/.codex-plugin/plugin.json" "$PROJECT/.codex-plugin/plugin.json"

expect_success() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'PASS version bump: %s\n' "$name"
  else
    printf 'FAIL version bump: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_failure() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'FAIL version bump rejected: %s\n' "$name"
    FAILURES=$((FAILURES + 1))
  else
    printf 'PASS version bump rejected: %s\n' "$name"
  fi
}

expect_failure "missing version" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$BUMP"
expect_failure "leading v" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$BUMP" v0.13.0
expect_failure "prerelease version" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$BUMP" 0.13.0-beta.1
expect_failure "same version" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$BUMP" 0.12.0
expect_failure "downgrade" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$BUMP" 0.11.0
expect_success "updates a greater stable release" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$BUMP" 0.13.0

if PROJECT_ROOT="$PROJECT" node -e '
  const fs = require("fs");
  const root = process.env.PROJECT_ROOT;
  const versions = [
    JSON.parse(fs.readFileSync(`${root}/.claude-plugin/plugin.json`)).version,
    JSON.parse(fs.readFileSync(`${root}/.codex-plugin/plugin.json`)).version,
    JSON.parse(fs.readFileSync(`${root}/.claude-plugin/marketplace.json`)).plugins.find((entry) => entry.name === "ducktutor").version,
  ];
  if (!versions.every((version) => version === "0.13.0")) process.exit(1);
'; then
  printf 'PASS version bump: keeps all manifests synchronized\n'
else
  printf 'FAIL version bump: keeps all manifests synchronized\n'
  FAILURES=$((FAILURES + 1))
fi

PROJECT_ROOT="$PROJECT" node -e '
  const fs = require("fs");
  const path = `${process.env.PROJECT_ROOT}/.codex-plugin/plugin.json`;
  const manifest = JSON.parse(fs.readFileSync(path, "utf8"));
  manifest.version = "0.13.1";
  fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
'
expect_failure "pre-existing manifest drift" env DUCKTUTOR_PROJECT_DIR="$PROJECT" "$BUMP" 0.14.0

if (( FAILURES > 0 )); then
  printf '%s version-bump test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All version-bump tests passed\n'
