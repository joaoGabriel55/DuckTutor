#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$ROOT}"
NEXT_VERSION="${1:-}"

if [[ "$#" -ne 1 || ! "$NEXT_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'Usage: scripts/bump-version.sh <major.minor.patch>\n' >&2
  exit 2
fi

node - "$PROJECT_DIR" "$NEXT_VERSION" <<'NODE'
const fs = require("fs");
const path = require("path");

const [, , root, nextVersion] = process.argv;
const targets = [
  { path: ".claude-plugin/plugin.json", get: (value) => value.version, set: (value) => { value.version = nextVersion; } },
  { path: ".codex-plugin/plugin.json", get: (value) => value.version, set: (value) => { value.version = nextVersion; } },
  {
    path: ".claude-plugin/marketplace.json",
    get(value) {
      const plugin = value.plugins?.find((entry) => entry.name === "ducktutor");
      if (!plugin) throw new Error(".claude-plugin/marketplace.json has no ducktutor entry");
      return plugin.version;
    },
    set(value) {
      value.plugins.find((entry) => entry.name === "ducktutor").version = nextVersion;
    },
  },
];

function parseVersion(value) {
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value || "")) {
    throw new Error(`unsupported current release version: ${JSON.stringify(value)}`);
  }
  const parts = value.split(".").map(Number);
  if (!parts.every(Number.isSafeInteger)) throw new Error(`release version is too large: ${value}`);
  return parts;
}

function compare(left, right) {
  for (let index = 0; index < 3; index += 1) {
    if (left[index] !== right[index]) return left[index] - right[index];
  }
  return 0;
}

try {
  const documents = targets.map((target) => {
    const absolutePath = path.join(root, target.path);
    return { ...target, absolutePath, value: JSON.parse(fs.readFileSync(absolutePath, "utf8")) };
  });
  const versions = documents.map((document) => document.get(document.value));
  if (new Set(versions).size !== 1) {
    throw new Error(`plugin versions are out of sync: ${versions.join(", ")}`);
  }
  const currentVersion = versions[0];
  if (compare(parseVersion(nextVersion), parseVersion(currentVersion)) <= 0) {
    throw new Error(`new version ${nextVersion} must be greater than ${currentVersion}`);
  }

  for (const document of documents) document.set(document.value);
  for (const document of documents) {
    const temporary = `${document.absolutePath}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(document.value, null, 2)}\n`);
    fs.renameSync(temporary, document.absolutePath);
  }
  process.stdout.write(`DuckTutor version bumped from ${currentVersion} to ${nextVersion}.\n`);
  process.stdout.write("Review the manifest diff, run validation, then commit, tag, and create the GitHub release.\n");
} catch (error) {
  process.stderr.write(`DuckTutor release: ${error.message}\n`);
  process.exit(1);
}
NODE
