#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD="$(cat 2>/dev/null || true)"

PAYLOAD_JSON="$PAYLOAD" CLEAN_SCRIPT="$ROOT/scripts/clean.sh" node -e '
  const { spawnSync } = require("child_process");
  let payload = {};
  try { payload = JSON.parse(process.env.PAYLOAD_JSON || "{}"); } catch (_) {}
  const cwd = typeof payload.cwd === "string" ? payload.cwd : process.cwd();
  const argument = typeof payload.command_args === "string" ? payload.command_args.trim() : "";
  const args = argument ? [argument] : [];
  const result = spawnSync(process.env.CLEAN_SCRIPT, args, {
    cwd,
    encoding: "utf8",
    env: { ...process.env, DUCKTUTOR_PROJECT_DIR: cwd },
  });
  const output = (result.status === 0 ? result.stdout : result.stderr).trim() ||
    "DuckTutor clean could not run.";
  process.stdout.write(JSON.stringify({ decision: "block", reason: output }) + "\n");
'
