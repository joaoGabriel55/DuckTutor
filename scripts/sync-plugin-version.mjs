#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const defaultRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const root = path.resolve(process.env.DUCKTUTOR_PROJECT_DIR || defaultRoot);
const packageManifest = readJson("package.json");
const nextVersion = packageManifest.version;
const targets = [
  { path: ".claude-plugin/plugin.json", get: (value) => value.version, set: setVersion },
  { path: ".codex-plugin/plugin.json", get: (value) => value.version, set: setVersion },
  {
    path: ".claude-plugin/marketplace.json",
    get(value) {
      return findMarketplacePlugin(value).version;
    },
    set(value) {
      findMarketplacePlugin(value).version = nextVersion;
    },
  },
];

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
}

function setVersion(value) {
  value.version = nextVersion;
}

function findMarketplacePlugin(value) {
  const plugin = value.plugins?.find((entry) => entry.name === "ducktutor");
  if (!plugin) throw new Error(".claude-plugin/marketplace.json has no ducktutor entry");
  return plugin;
}

function parseVersion(value, label) {
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value || "")) {
    throw new Error(`${label} has unsupported version ${JSON.stringify(value)}`);
  }
  const parts = value.split(".").map(Number);
  if (!parts.every(Number.isSafeInteger)) throw new Error(`${label} version is too large: ${value}`);
  return parts;
}

function compare(left, right) {
  for (let index = 0; index < 3; index += 1) {
    if (left[index] !== right[index]) return left[index] - right[index];
  }
  return 0;
}

function writeJson(relativePath, value) {
  const absolutePath = path.join(root, relativePath);
  const temporaryPath = `${absolutePath}.${process.pid}.tmp`;
  fs.writeFileSync(temporaryPath, `${JSON.stringify(value, null, 2)}\n`);
  fs.renameSync(temporaryPath, absolutePath);
}

try {
  const parsedNextVersion = parseVersion(nextVersion, "package.json");
  const documents = targets.map((target) => ({ ...target, value: readJson(target.path) }));
  const currentVersions = documents.map((document) => document.get(document.value));
  if (new Set(currentVersions).size !== 1) {
    throw new Error(`plugin versions are out of sync: ${currentVersions.join(", ")}`);
  }

  const currentVersion = currentVersions[0];
  const comparison = compare(parsedNextVersion, parseVersion(currentVersion, "plugin manifests"));
  if (comparison < 0) {
    throw new Error(`package version ${nextVersion} is older than plugin version ${currentVersion}`);
  }
  if (comparison === 0) {
    process.stdout.write(`Plugin manifests already use ${nextVersion}.\n`);
    process.exit(0);
  }

  for (const document of documents) document.set(document.value);
  for (const document of documents) writeJson(document.path, document.value);
  process.stdout.write(`Plugin manifests synchronized from ${currentVersion} to ${nextVersion}.\n`);
} catch (error) {
  process.stderr.write(`DuckTutor version sync: ${error.message}\n`);
  process.exit(1);
}
