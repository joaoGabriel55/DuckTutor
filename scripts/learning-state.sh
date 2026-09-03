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
  engagedCommands: [],
  activeCommand: null,
  implementationMode: "hybrid",
  checkpointRequired: false,
  checkpointRequestedAt: null,
  checkpointCompletedAt: null,
  lastAbandonedTask: null,
  lastAbandonedAt: null,
  unexplainedAgentChanges: [],
  updatedAt: null,
  stale: false,
  staleReason: null,
};

function withFreshness(value) {
  if (value.phase === "idle" && value.engagedCommands.length === 0 && !value.checkpointRequired) {
    return { ...value, stale: false, staleReason: null };
  }
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
    if (value.schema !== 1 || !Array.isArray(value.learnerPaths) || !Array.isArray(value.agentPaths) ||
        (value.unexplainedAgentChanges !== undefined && !Array.isArray(value.unexplainedAgentChanges))) {
      fail("stored state has an unsupported shape");
    }
    return withFreshness({
      ...idle,
      ...value,
      engagedCommands: Array.isArray(value.engagedCommands) ? value.engagedCommands : [],
      checkpointRequired: value.checkpointRequired === true,
      unexplainedAgentChanges: activeUnexplainedChanges(value.unexplainedAgentChanges || []),
    });
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

function workingTreePaths() {
  const result = spawnSync("git", ["-C", repositoryRoot, "status", "--porcelain=v1", "-z", "--untracked-files=all"], {
    encoding: "utf8",
  });
  if (result.status !== 0) return new Set();
  const entries = result.stdout.split("\0").filter(Boolean);
  const changed = new Set();
  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index];
    changed.add(entry.slice(3).replaceAll("\\", "/"));
    if (/[RC]/.test(entry.slice(0, 2)) && entries[index + 1]) {
      changed.add(entries[index + 1].replaceAll("\\", "/"));
      index += 1;
    }
  }
  return changed;
}

function activeUnexplainedChanges(records) {
  if (!records.length) return [];
  const changed = workingTreePaths();
  const seen = new Set();
  const validBaselines = new Map();
  const active = [];
  for (const record of [...records].reverse()) {
    if (!record || typeof record.task !== "string" || record.branch !== currentBranch ||
        typeof record.retiredAt !== "string" || !Array.isArray(record.paths)) continue;
    const baseline = record.baselineHead ?? null;
    if (!validBaselines.has(baseline)) {
      const valid = baseline && currentHead
        ? spawnSync("git", ["-C", repositoryRoot, "merge-base", "--is-ancestor", baseline, currentHead]).status === 0
        : baseline === currentHead;
      validBaselines.set(baseline, valid);
    }
    if (!validBaselines.get(baseline)) continue;
    const paths = record.paths.filter((candidate) =>
      typeof candidate === "string" && changed.has(candidate) && !seen.has(candidate));
    paths.forEach((candidate) => seen.add(candidate));
    if (paths.length) active.push({ ...record, paths });
  }
  return active.reverse();
}

function retirePendingTask(state) {
  const retiredAt = new Date().toISOString();
  const changed = state.stale ? new Set() : workingTreePaths();
  const paths = state.agentPaths.filter((candidate) => changed.has(candidate));
  return {
    lastAbandonedTask: state.task,
    lastAbandonedAt: retiredAt,
    unexplainedAgentChanges: paths.length
      ? [...state.unexplainedAgentChanges, {
          task: state.task,
          paths,
          branch: state.branch,
          baselineHead: state.baselineHead,
          retiredAt,
        }]
      : state.unexplainedAgentChanges,
  };
}

switch (command) {
  case "show":
    process.stdout.write(`${JSON.stringify(readState())}\n`);
    break;
  case "begin": {
    const current = readState();
    if (current.checkpointRequired) fail("complete the required comprehension checkpoint first");
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
      engagedCommands: current.engagedCommands,
      activeCommand: current.activeCommand,
      implementationMode: current.implementationMode,
      checkpointCompletedAt: current.checkpointCompletedAt,
      lastAbandonedTask: current.lastAbandonedTask,
      lastAbandonedAt: current.lastAbandonedAt,
      unexplainedAgentChanges: current.unexplainedAgentChanges,
    });
    break;
  }
  case "engage": {
    const current = readState();
    const entry = args[0];
    const commands = ["teach-me", "start", "explain", "review", "hint", "checkpoint", "implement"];
    const forceAgent = entry === "implement" && args.length === 2 && args[1] === "--force-agent";
    const newTask = entry === "start" && args.length === 2 && args[1] === "--new-task";
    if ((!forceAgent && !newTask && args.length !== 1) || !commands.includes(entry)) {
      fail("engage requires a DuckTutor command name; implement accepts --force-agent and start accepts --new-task");
    }
    if (current.checkpointRequired && entry !== "checkpoint" && !newTask) {
      fail("answer the required comprehension checkpoint before using another DuckTutor command");
    }
    if (newTask) {
      const retiresPendingTask = current.checkpointRequired && Boolean(current.task);
      const retired = retiresPendingTask ? retirePendingTask(current) : null;
      writeState({
        ...idle,
        repositoryRoot,
        branch: currentBranch,
        baselineHead: currentHead,
        engagedCommands: [...new Set([...current.engagedCommands, entry])],
        activeCommand: entry,
        lastAbandonedTask: retired?.lastAbandonedTask ?? current.lastAbandonedTask,
        lastAbandonedAt: retired?.lastAbandonedAt ?? current.lastAbandonedAt,
        unexplainedAgentChanges: retired?.unexplainedAgentChanges ?? current.unexplainedAgentChanges,
      });
      break;
    }
    if (current.stale) fail(`state is stale: ${current.staleReason}; clear it before continuing`);
    if (entry === "implement" && !current.engagedCommands.some((command) => command !== "implement")) {
      fail("run any other DuckTutor command before implement");
    }
    writeState({
      ...current,
      repositoryRoot: current.repositoryRoot || repositoryRoot,
      branch: current.branch || currentBranch,
      baselineHead: current.baselineHead ?? currentHead,
      engagedCommands: [...new Set([...current.engagedCommands, entry])],
      activeCommand: entry,
      implementationMode: entry === "implement" ? (forceAgent ? "force-agent" : "hybrid") : current.implementationMode,
    });
    break;
  }
  case "checkpoint": {
    const current = readState();
    const action = args[0];
    if (action === "abandon" && args.length === 2 && args[1] === "developer-confirmed") {
      if (!current.checkpointRequired) fail("no comprehension checkpoint is pending");
      const retiredAt = new Date().toISOString();
      writeState({
        ...idle,
        repositoryRoot,
        branch: currentBranch,
        baselineHead: currentHead,
        engagedCommands: current.engagedCommands,
        activeCommand: "checkpoint",
        lastAbandonedTask: current.task,
        lastAbandonedAt: retiredAt,
        unexplainedAgentChanges: current.unexplainedAgentChanges,
      });
    } else if (current.stale) {
      fail(`state is stale: ${current.staleReason}`);
    } else if (action === "require" && args.length === 1) {
      if (!["predicted", "attempted", "verified"].includes(current.phase)) fail("an active implementation is required");
      writeState({
        ...current,
        checkpointRequired: true,
        checkpointRequestedAt: current.checkpointRequestedAt || new Date().toISOString(),
      });
    } else if (action === "pass" && args.length === 2 && args[1] === "developer-confirmed") {
      if (!current.checkpointRequired) fail("no comprehension checkpoint is pending");
      writeState({
        ...current,
        checkpointRequired: false,
        checkpointRequestedAt: null,
        checkpointCompletedAt: new Date().toISOString(),
      });
    } else {
      fail("checkpoint requires require, pass developer-confirmed, or abandon developer-confirmed");
    }
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
    if (current.implementationMode === "force-agent") {
      if (agentPaths.length === 0) fail("force-agent scope requires at least one agent-owned file");
    } else if (learnerPaths.length === 0) {
      fail("scope requires at least one learner-owned file unless force-agent mode is active");
    }
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
    if (next === "explained" && current.checkpointRequired) {
      fail("complete the required comprehension checkpoint before explained");
    }
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
    if (readState().checkpointRequired) fail("complete the required comprehension checkpoint before clearing state");
    try {
      fs.unlinkSync(statePath);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    process.stdout.write(`${JSON.stringify(idle)}\n`);
    break;
  default:
    fail("supported commands are show, begin, scope, phase, engage, checkpoint, and clear");
}
NODE
