#!/usr/bin/env bash

set -uo pipefail

PROJECT_DIR="${DUCKTUTOR_PROJECT_DIR:-$PWD}"
COMMAND="${1:-show}"

if [[ "$COMMAND" != "show" || "$#" -ne 1 ]]; then
  printf 'DuckTutor project context: supported command is show\n' >&2
  exit 1
fi

node - "$PROJECT_DIR" <<'NODE'
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const projectDir = process.argv[2];
const rootResult = spawnSync("git", ["-C", projectDir, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
if (rootResult.status !== 0) {
  process.stderr.write("DuckTutor project context: current directory is not in a Git repository\n");
  process.exit(1);
}

const root = fs.realpathSync(rootResult.stdout.trim());
const current = fs.realpathSync(projectDir);
const relativeCurrent = path.relative(root, current);
if (relativeCurrent === ".." || relativeCurrent.startsWith(`..${path.sep}`)) process.exit(1);

const ignoredDirectories = new Set([".git", "node_modules", "vendor", "dist", "build", "coverage"]);
const filesResult = spawnSync(
  "git",
  ["-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
  { encoding: "utf8", maxBuffer: 4 * 1024 * 1024 },
);
if (filesResult.status !== 0) process.exit(1);
const allFiles = filesResult.stdout.split("\0").filter(Boolean).filter((file) => {
  const segments = file.split("/");
  if (segments.some((segment) => ignoredDirectories.has(segment))) return false;
  const absolute = path.join(root, file);
  return fs.existsSync(absolute) && fs.lstatSync(absolute).isFile();
});

const instructionNames = ["AGENTS.override.md", "AGENTS.md", "CLAUDE.md", "CONTEXT.md"];
const applicableInstructions = [];
let cursor = root;
const currentSegments = relativeCurrent ? relativeCurrent.split(path.sep) : [];
for (const segment of ["", ...currentSegments]) {
  if (segment) cursor = path.join(cursor, segment);
  for (const name of instructionNames) {
    if (name === "AGENTS.md" && fs.existsSync(path.join(cursor, "AGENTS.override.md"))) continue;
    const candidate = path.join(cursor, name);
    if (fs.existsSync(candidate) && fs.lstatSync(candidate).isFile()) {
      applicableInstructions.push(path.relative(root, candidate).split(path.sep).join("/"));
    }
  }
}

function selected(predicate, limit = 40) {
  return allFiles.filter(predicate).sort().slice(0, limit);
}

const projectInstructions = selected((file) =>
  instructionNames.includes(path.posix.basename(file)) || file === ".github/copilot-instructions.md");
const skills = selected((file) =>
  /(?:^|\/)\.(?:agents|codex|claude)\/skills\/.+\/SKILL\.md$/.test(file));
const automation = selected((file) =>
  /(?:^|\/)\.github\/workflows\/[^/]+\.(?:ya?ml)$/.test(file) ||
  /(?:^|\/)\.(?:claude|codex)\/hooks\//.test(file) ||
  /(?:^|\/)hooks\/hooks\.json$/.test(file) ||
  /(?:^|\/)\.(?:claude|codex)\/hooks\.json$/.test(file) ||
  /(?:^|\/)\.claude\/settings(?:\.local)?\.json$/.test(file) ||
  /(?:^|\/)\.codex\/config\.toml$/.test(file) ||
  /(?:^|\/)\.mcp\.json$/.test(file));
const referenceNames = new Set([
  "README.md", "CONTRIBUTING.md", "package.json", "pnpm-workspace.yaml", "pyproject.toml",
  "Cargo.toml", "go.mod", "Gemfile", "Makefile", "Taskfile.yml", "Taskfile.yaml", "justfile",
]);
const references = selected((file) => referenceNames.has(path.posix.basename(file)));

process.stdout.write(`${JSON.stringify({
  schema: 1,
  repositoryRoot: root,
  workingDirectory: current,
  applicableInstructions,
  projectInstructions,
  skills,
  automation,
  references,
})}\n`);
NODE
