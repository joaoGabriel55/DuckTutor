#!/usr/bin/env bash

set -uo pipefail

PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}"

node - "$PROJECT_DIR" "$@" <<'NODE'
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const [, , projectDir, command = "show", ...args] = process.argv;
const phases = ["grounded", "predicted", "attempted", "verified", "explained"];

function fail(message) {
  process.stderr.write(`DuckTutor state: ${message}\n`);
  process.exit(1);
}

const gitDirResult = spawnSync("git", ["-C", projectDir, "rev-parse", "--absolute-git-dir"], {
  encoding: "utf8",
});
if (gitDirResult.status !== 0) fail("the current project is not a Git repository");

const stateDir = path.join(gitDirResult.stdout.trim(), "ducktutor");
const statePath = path.join(stateDir, "state.json");
const repositoryRootResult = spawnSync("git", ["-C", projectDir, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
const branchResult = spawnSync("git", ["-C", projectDir, "branch", "--show-current"], { encoding: "utf8" });
const headResult = spawnSync("git", ["-C", projectDir, "rev-parse", "HEAD"], { encoding: "utf8" });
const repositoryRoot = fs.realpathSync(repositoryRootResult.stdout.trim());
const currentBranch = branchResult.stdout.trim() || "detached";
const currentHead = headResult.status === 0 ? headResult.stdout.trim() : null;
const idle = {
  schema: 1,
  task: "",
  phase: "idle",
  learnerPaths: [],
  agentPaths: [],
  repositoryRoot: null,
  branch: null,
  baselineHead: null,
  explanationConfirmedAt: null,
  updatedAt: null,
  stale: false,
  staleReason: null,
};

function withFreshness(value) {
  if (value.phase === "idle") return { ...value, stale: false, staleReason: null };
  let staleReason = null;
  if (value.repositoryRoot !== repositoryRoot) {
    staleReason = "repository changed";
  } else if (value.branch !== currentBranch) {
    staleReason = `branch changed from ${value.branch} to ${currentBranch}`;
  } else if (value.baselineHead && currentHead) {
    const ancestor = spawnSync("git", ["-C", projectDir, "merge-base", "--is-ancestor", value.baselineHead, currentHead]);
    if (ancestor.status !== 0) staleReason = "HEAD no longer descends from the approved baseline";
  } else if (value.baselineHead !== currentHead) {
    staleReason = "HEAD changed from or to an unborn branch";
  }
  return { ...value, stale: Boolean(staleReason), staleReason };
}

function readState() {
  try {
    const value = JSON.parse(fs.readFileSync(statePath, "utf8"));
    if (value.schema !== 1 || !Array.isArray(value.learnerPaths) || !Array.isArray(value.agentPaths)) {
      fail("stored state has an unsupported shape");
    }
    return withFreshness(value);
  } catch (error) {
    if (error.code === "ENOENT") return { ...idle };
    if (error instanceof SyntaxError) fail("stored state is invalid JSON");
    throw error;
  }
}

function writeState(value) {
  fs.mkdirSync(stateDir, { recursive: true, mode: 0o700 });
  const { stale: _stale, staleReason: _staleReason, ...stored } = value;
  const next = { ...stored, schema: 1, updatedAt: new Date().toISOString() };
  const temporary = `${statePath}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temporary, statePath);
  process.stdout.write(`${JSON.stringify(next)}\n`);
}

function normalizeProjectPath(raw) {
  const value = raw.replaceAll("\\", "/").replace(/^\.\//, "");
  const segments = value.split("/");
  if (
    !value ||
    value.includes("\0") ||
    path.posix.isAbsolute(value) ||
    /^[A-Za-z]:\//.test(value) ||
    segments.some((segment) => segment === "" || segment === ".." || segment === ".git")
  ) {
    fail(`invalid project-relative path: ${raw}`);
  }
  return path.posix.normalize(value);
}

switch (command) {
  case "show":
    process.stdout.write(`${JSON.stringify(readState())}\n`);
    break;
  case "begin": {
    const task = args.join(" ").trim();
    if (!task || task.length > 200 || /[\u0000-\u001f\u007f]/.test(task)) {
      fail("begin requires a single-line task summary of at most 200 characters");
    }
    writeState({
      ...idle,
      task,
      phase: "grounded",
      repositoryRoot,
      branch: currentBranch,
      baselineHead: currentHead,
    });
    break;
  }
  case "scope": {
    const current = readState();
    if (current.phase === "idle") fail("begin a task before setting its ownership map");
    if (current.stale) fail(`state is stale: ${current.staleReason}`);
    if (!["predicted", "attempted"].includes(current.phase)) {
      fail("ownership can change only during the predicted or attempted phase");
    }
    if (args.length === 0) fail("scope requires at least one learner: or agent: path");
    const learnerPaths = [];
    const agentPaths = [];
    for (const entry of args) {
      const separator = entry.indexOf(":");
      const owner = entry.slice(0, separator);
      const rawPath = entry.slice(separator + 1);
      if (separator < 1 || (owner !== "learner" && owner !== "agent")) {
        fail(`invalid ownership entry: ${entry}`);
      }
      const normalized = normalizeProjectPath(rawPath);
      (owner === "learner" ? learnerPaths : agentPaths).push(normalized);
    }
    if (new Set(learnerPaths).size !== learnerPaths.length || new Set(agentPaths).size !== agentPaths.length) {
      fail("ownership paths must be unique");
    }
    const overlap = learnerPaths.find((entry) => agentPaths.includes(entry));
    if (overlap) fail(`a path cannot have two owners: ${overlap}`);
    if (learnerPaths.length === 0) fail("scope requires at least one learner-owned file");
    writeState({ ...current, learnerPaths, agentPaths });
    break;
  }
  case "phase": {
    const current = readState();
    const next = args[0];
    const explanationConfirmed = next === "explained" && args[1] === "developer-confirmed";
    const expectedArgs = next === "explained" ? 2 : 1;
    if (args.length !== expectedArgs || !phases.includes(next) || (next === "explained" && !explanationConfirmed)) {
      fail("phase requires a valid phase name; explained also requires developer-confirmed");
    }
    if (current.stale) fail(`state is stale: ${current.staleReason}`);
    const currentIndex = phases.indexOf(current.phase);
    const nextIndex = phases.indexOf(next);
    if (currentIndex < 0 || nextIndex !== currentIndex + 1) {
      fail(`phase must advance one step from ${current.phase}`);
    }
    if (next === "attempted" && current.learnerPaths.length + current.agentPaths.length === 0) {
      fail("set an ownership map before recording an attempt");
    }
    writeState({
      ...current,
      phase: next,
      explanationConfirmedAt: explanationConfirmed ? new Date().toISOString() : current.explanationConfirmedAt,
    });
    break;
  }
  case "clear":
    try {
      fs.unlinkSync(statePath);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    process.stdout.write(`${JSON.stringify(idle)}\n`);
    break;
  default:
    fail("supported commands are show, begin, scope, phase, and clear");
}
NODE
