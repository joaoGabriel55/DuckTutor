#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$ROOT/scripts/sync-plugin-version.mjs"
PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/ducktutor-version-sync.XXXXXX")"
FAILURES=0

cleanup() { rm -rf "$PROJECT"; }
trap cleanup EXIT

mkdir -p "$PROJECT/.claude-plugin" "$PROJECT/.codex-plugin"
mkdir -p "$PROJECT/.changeset"
cp "$ROOT/package.json" "$PROJECT/package.json"
cp "$ROOT/.changeset/config.json" "$PROJECT/.changeset/config.json"
cp "$ROOT/.claude-plugin/plugin.json" "$PROJECT/.claude-plugin/plugin.json"
cp "$ROOT/.claude-plugin/marketplace.json" "$PROJECT/.claude-plugin/marketplace.json"
cp "$ROOT/.codex-plugin/plugin.json" "$PROJECT/.codex-plugin/plugin.json"
ln -s "$ROOT/node_modules" "$PROJECT/node_modules"

set_package_version() {
  PROJECT_ROOT="$PROJECT" TARGET_VERSION="$1" node -e '
    const fs = require("fs");
    const root = process.env.PROJECT_ROOT;
    const manifest = JSON.parse(fs.readFileSync(`${root}/package.json`, "utf8"));
    manifest.version = process.env.TARGET_VERSION;
    fs.writeFileSync(`${root}/package.json`, `${JSON.stringify(manifest, null, 2)}\n`);
  '
}

if grep -q 'changesets/action@v1' "$ROOT/.github/workflows/changesets.yml" &&
   grep -q 'version: pnpm run version' "$ROOT/.github/workflows/changesets.yml" &&
   node -e '
     const fs = require("fs");
     const root = process.argv[1];
     const pkg = JSON.parse(fs.readFileSync(`${root}/package.json`, "utf8"));
     const config = JSON.parse(fs.readFileSync(`${root}/.changeset/config.json`, "utf8"));
     if (!pkg.private || pkg.scripts?.version !== "changeset version && node scripts/sync-plugin-version.mjs") process.exit(1);
     if (!config.privatePackages?.version || config.privatePackages?.tag) process.exit(1);
   ' "$ROOT"; then
  printf 'PASS version automation: workflow runs the configured Changesets version command\n'
else
  printf 'FAIL version automation: workflow runs the configured Changesets version command\n'
  FAILURES=$((FAILURES + 1))
fi

PROJECT_ROOT="$PROJECT" node -e '
  const fs = require("fs");
  const path = `${process.env.PROJECT_ROOT}/.changeset/config.json`;
  const config = JSON.parse(fs.readFileSync(path, "utf8"));
  config.changelog = false;
  fs.writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`);
'
printf '%s\n' '---' '"duck-tutor": patch' '---' '' 'Exercise the automated plugin version sync.' > "$PROJECT/.changeset/version-sync-test.md"
git -C "$PROJECT" init -q

if (cd "$PROJECT" && "$ROOT/node_modules/.bin/changeset" version >/dev/null) &&
   DUCKTUTOR_PROJECT_DIR="$PROJECT" node "$SYNC" >/dev/null && PROJECT_ROOT="$PROJECT" node -e '
  const fs = require("fs");
  const root = process.env.PROJECT_ROOT;
  const versions = [
    JSON.parse(fs.readFileSync(`${root}/package.json`, "utf8")).version,
    JSON.parse(fs.readFileSync(`${root}/.claude-plugin/plugin.json`, "utf8")).version,
    JSON.parse(fs.readFileSync(`${root}/.codex-plugin/plugin.json`, "utf8")).version,
    JSON.parse(fs.readFileSync(`${root}/.claude-plugin/marketplace.json`, "utf8")).plugins.find((entry) => entry.name === "ducktutor").version,
  ];
  if (!versions.every((version) => version === "0.14.1")) process.exit(1);
'; then
  printf 'PASS version automation: Changesets version propagates to every plugin manifest\n'
else
  printf 'FAIL version automation: Changesets version propagates to every plugin manifest\n'
  FAILURES=$((FAILURES + 1))
fi

if DUCKTUTOR_PROJECT_DIR="$PROJECT" node "$SYNC" >/dev/null; then
  printf 'PASS version automation: synchronized versions are idempotent\n'
else
  printf 'FAIL version automation: synchronized versions are idempotent\n'
  FAILURES=$((FAILURES + 1))
fi

set_package_version 0.13.0
if DUCKTUTOR_PROJECT_DIR="$PROJECT" node "$SYNC" >/dev/null 2>&1; then
  printf 'FAIL version automation: package downgrade is rejected\n'
  FAILURES=$((FAILURES + 1))
else
  printf 'PASS version automation: package downgrade is rejected\n'
fi

if (( FAILURES > 0 )); then
  printf '%s version-automation test(s) failed\n' "$FAILURES"
  exit 1
fi

printf 'All version-automation tests passed\n'
