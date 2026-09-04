#!/usr/bin/env bash

set -uo pipefail

PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}"

node - "$PROJECT_DIR" "$@" <<'NODE'
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const [, , projectDir, command = "show", ...args] = process.argv;
const phases = ["grounded", "predicted", "attempted", "verified", "assessed"];

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
  schema: 4,
  task: "",
  phase: "idle",
  learnerPaths: [],
  agentPaths: [],
  repositoryRoot: null,
  branch: null,
  baselineHead: null,
  responseMode: "quiz",
  deepReflectionRequired: false,
  assessmentConfirmedAt: null,
  assessmentMode: null,
  engagedCommands: [],
  activeCommand: null,
  implementationMode: "hybrid",
  checkpointRequired: false,
  quizQuestionsAnswered: 0,
  quizCorrectAnswers: 0,
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
    if (![1, 2, 3, 4].includes(value.schema) || !Array.isArray(value.learnerPaths) || !Array.isArray(value.agentPaths) ||
        (value.unexplainedAgentChanges !== undefined && !Array.isArray(value.unexplainedAgentChanges))) {
      fail("stored state has an unsupported shape");
    }
    const {
      explanationConfirmedAt: legacyExplanationConfirmedAt,
      quizConfirmedAt: legacyQuizConfirmedAt,
      ...stored
    } = value;
    return withFreshness({
      ...idle,
      ...stored,
      schema: 4,
      phase: value.phase === "explained" ? "assessed" : value.phase,
      responseMode: ["quiz", "free-text"].includes(value.responseMode) ? value.responseMode : "quiz",
      deepReflectionRequired: value.deepReflectionRequired === true,
      assessmentConfirmedAt: value.assessmentConfirmedAt ?? legacyQuizConfirmedAt ?? legacyExplanationConfirmedAt ?? null,
      assessmentMode: value.assessmentMode ?? (legacyQuizConfirmedAt ? "quiz" : legacyExplanationConfirmedAt ? "free-text" : null),
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
  const next = { ...stored, schema: 4, updatedAt: new Date().toISOString() };
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
      responseMode: current.responseMode,
      deepReflectionRequired: current.implementationMode === "force-agent" && current.deepReflectionRequired,
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
        responseMode: current.responseMode,
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
      deepReflectionRequired: current.deepReflectionRequired || forceAgent,
    });
    break;
  }
  case "checkpoint": {
    const current = readState();
    const action = args[0];
    if (action === "abandon" && args.length === 2 && args[1] === "choice-confirmed") {
      if (!current.checkpointRequired) fail("no comprehension checkpoint is pending");
      const retiredAt = new Date().toISOString();
      writeState({
        ...idle,
        repositoryRoot,
        branch: currentBranch,
        baselineHead: currentHead,
        engagedCommands: current.engagedCommands,
        activeCommand: "checkpoint",
        responseMode: current.responseMode,
        lastAbandonedTask: current.task,
        lastAbandonedAt: retiredAt,
        unexplainedAgentChanges: current.unexplainedAgentChanges,
      });
    } else if (current.stale) {
      fail(`state is stale: ${current.staleReason}`);
    } else if (action === "require" && (args.length === 1 || (args.length === 2 && args[1] === "deep-reflection"))) {
      if (!["predicted", "attempted", "verified"].includes(current.phase)) fail("an active implementation is required");
      writeState({
        ...current,
        deepReflectionRequired: current.deepReflectionRequired || args[1] === "deep-reflection",
        checkpointRequired: true,
        quizQuestionsAnswered: 0,
        quizCorrectAnswers: 0,
        checkpointRequestedAt: current.checkpointRequestedAt || new Date().toISOString(),
        checkpointCompletedAt: null,
        assessmentMode: null,
      });
    } else if (action === "record" && args.length === 2 && ["correct", "incorrect", "unsure"].includes(args[1])) {
      if (!current.checkpointRequired) fail("no adaptive quiz checkpoint is pending");
      if (current.responseMode !== "quiz" || current.deepReflectionRequired) {
        fail("quiz results can be recorded only when the effective checkpoint mode is quiz");
      }
      if (current.quizQuestionsAnswered >= 3) fail("the adaptive quiz already reached its three-question limit");
      writeState({
        ...current,
        quizQuestionsAnswered: current.quizQuestionsAnswered + 1,
        quizCorrectAnswers: current.quizCorrectAnswers + (args[1] === "correct" ? 1 : 0),
      });
    } else if (action === "pass" && args.length === 2 && ["quiz-confirmed", "free-text-confirmed"].includes(args[1])) {
      if (!current.checkpointRequired) fail("no comprehension checkpoint is pending");
      const effectiveMode = current.deepReflectionRequired ? "deep-reflection" : current.responseMode;
      const expectedToken = effectiveMode === "quiz" ? "quiz-confirmed" : "free-text-confirmed";
      if (args[1] !== expectedToken) fail(`checkpoint completion requires ${expectedToken} in ${effectiveMode} mode`);
      if (effectiveMode === "quiz" && (current.quizQuestionsAnswered < 2 || current.quizCorrectAnswers < 2)) {
        fail("adaptive quiz requires two correct answers within three questions");
      }
      writeState({
        ...current,
        checkpointRequired: false,
        checkpointRequestedAt: null,
        checkpointCompletedAt: new Date().toISOString(),
        assessmentMode: effectiveMode,
      });
    } else {
      fail("checkpoint requires require [deep-reflection], record correct|incorrect|unsure, a mode-matched pass token, or abandon choice-confirmed");
    }
    break;
  }
  case "config": {
    const current = readState();
    if (args.length !== 3 || args[0] !== "set" || !["quiz", "free-text"].includes(args[1]) || args[2] !== "argument-confirmed") {
      fail("config requires set quiz|free-text argument-confirmed");
    }
    const responseMode = args[1];
    const changed = responseMode !== current.responseMode;
    const completedButUnassessed = changed && current.phase === "verified" && Boolean(current.checkpointCompletedAt);
    writeState({
      ...current,
      repositoryRoot: current.phase === "idle" ? repositoryRoot : current.repositoryRoot,
      branch: current.phase === "idle" ? currentBranch : current.branch,
      baselineHead: current.phase === "idle" ? currentHead : current.baselineHead,
      responseMode,
      quizQuestionsAnswered: changed ? 0 : current.quizQuestionsAnswered,
      quizCorrectAnswers: changed ? 0 : current.quizCorrectAnswers,
      checkpointRequired: completedButUnassessed ? true : current.checkpointRequired,
      checkpointRequestedAt: completedButUnassessed ? new Date().toISOString() : current.checkpointRequestedAt,
      checkpointCompletedAt: completedButUnassessed ? null : current.checkpointCompletedAt,
      assessmentMode: completedButUnassessed ? null : current.assessmentMode,
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
    if (current.implementationMode === "force-agent") {
      if (agentPaths.length === 0) fail("force-agent scope requires at least one agent-owned file");
    } else if (learnerPaths.length === 0) {
      fail("scope requires at least one learner-owned file unless force-agent mode is active");
    }
    const currentPaths = new Set([...current.learnerPaths, ...current.agentPaths]);
    const scopeExpanded = currentPaths.size > 0 && [...learnerPaths, ...agentPaths].some((candidate) => !currentPaths.has(candidate));
    writeState({
      ...current,
      learnerPaths,
      agentPaths,
      deepReflectionRequired: current.deepReflectionRequired || scopeExpanded,
    });
    break;
  }
  case "phase": {
    const current = readState();
    const next = args[0];
    const assessmentConfirmed = next === "assessed" && args[1] === "assessment-confirmed";
    const expectedArgs = next === "assessed" ? 2 : 1;
    if (args.length !== expectedArgs || !phases.includes(next) || (next === "assessed" && !assessmentConfirmed)) {
      fail("phase requires a valid phase name; assessed also requires assessment-confirmed");
    }
    if (current.stale) fail(`state is stale: ${current.staleReason}`);
    if (next === "assessed" && current.checkpointRequired) {
      fail("complete the required checkpoint before assessed");
    }
    if (next === "assessed" && (!current.checkpointCompletedAt || !current.assessmentMode)) {
      fail("record a completed checkpoint before assessed");
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
      assessmentConfirmedAt: assessmentConfirmed ? new Date().toISOString() : current.assessmentConfirmedAt,
    });
    break;
  }
  case "clear": {
    const current = readState();
    if (current.checkpointRequired) fail("complete the required comprehension checkpoint before clearing state");
    writeState({ ...idle, responseMode: current.responseMode });
    break;
  }
  case "clean": {
    if (args.length !== 1 || args[0] !== "argument-confirmed") {
      fail("clean requires argument-confirmed");
    }
    fs.rmSync(stateDir, { recursive: true, force: true });
    process.stdout.write(`${JSON.stringify(idle)}\n`);
    break;
  }
  default:
    fail("supported commands are show, begin, scope, phase, engage, checkpoint, config, clear, and clean");
}
NODE
