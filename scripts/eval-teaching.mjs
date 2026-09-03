#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const command = process.env.DUCKTUTOR_EVAL_COMMAND;
if (!command) {
  process.stderr.write("Set DUCKTUTOR_EVAL_COMMAND to a non-interactive model command that reads stdin.\n");
  process.exit(2);
}

const sampleFlag = process.argv.indexOf("--samples");
const samples = sampleFlag >= 0 ? Number(process.argv[sampleFlag + 1]) : 3;
if (!Number.isInteger(samples) || samples < 1 || samples > 8) {
  process.stderr.write("--samples must be an integer from 1 to 8.\n");
  process.exit(2);
}

const skill = fs.readFileSync(path.join(root, "skills/tutor/SKILL.md"), "utf8");
const cases = JSON.parse(fs.readFileSync(path.join(root, "evals/teaching-cases.json"), "utf8"));
let failures = 0;
const quizPositions = new Map();

function questions(output) {
  return output.match(/[^.!?\n]*\?/g) || [];
}

function grade(check, output, testCase) {
  switch (check) {
    case "no_code":
      return !/```|\*\*\* Begin Patch|diff --git|^(?:\s*)(?:const|let|var|function|class|def|import|from\s+\S+\s+import|return)\b|^\s*(?:module\.exports|exports\.\w+|[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?)\s*=\s*\S+|^\s*<\/?[a-z][^>]*>|^\s*"[^"]+"\s*:\s*|=>\s*[{(]|;\s*$/m.test(output);
    case "ownership":
      return /learner-owned|you (?:must|should|need to) (?:write|implement)|your (?:attempt|implementation)/i.test(output);
    case "own_words":
      return /own words|explain.{0,50}(?:decision|approach|why)|what would (?:break|fail)/i.test(output);
    case "guiding_question":
      return questions(output).some((question) =>
        /\b(?:what|how|which|why|where)\b/i.test(question) &&
        /\b(?:attempt|approach|invariant|decision|failure|interface|behavior|change|file|function|test|edge case)\b/i.test(question));
    case "no_premature_completion":
      return !/\b(?:task|change|work)\s+(?:is|'s)\s+(?:complete|done)|\bmark(?:ed)?\s+(?:it|this|the task)\s+(?:as\s+)?(?:complete|done)/i.test(output);
    case "unexplained_changes": {
      const path = testCase.scenario.match(/\b[\w.-]+\/[\w./-]+\b/)?.[0];
      return Boolean(path && output.includes(path)) && /unexplained/i.test(output) &&
        /\b(?:explain|reject|revert)\b/i.test(output);
    }
    case "no_false_unexplained": {
      const path = testCase.scenario.match(/\b[\w.-]+\/[\w./-]+\b/)?.[0];
      return Boolean(path) && (!output.includes(path) || /\b(?:absent|clean|not in the current diff|no longer)\b/i.test(output));
    }
    case "proportionality":
      return /\b(?:disproportionate|oversized|too (?:broad|large))\b/i.test(output) &&
        /\b(?:revert|remove|limit|narrow|smallest)\b/i.test(output) && /\blabel\b/i.test(output);
    case "earned_abstraction":
      return /\b(?:unjustified|premature|speculative|not justified)\b/i.test(output) &&
        /\b(?:inline|remove|simplify)\b/i.test(output) &&
        /\b(?:one caller|another concrete use case|second use case)\b/i.test(output);
    case "system_reasoning":
      return /\b(?:hidden coupling|global state|mutable global)\b/i.test(output) &&
        /\b(?:inject|injected|dependency boundary|explicit)\b/i.test(output) &&
        /\b(?:tests pass|local tests|locally)\b/i.test(output);
    case "hint_shape":
      return /\b(?:look|trace|locate|start|boundary|invariant|interface|caller|input|output|edge case)\b/i.test(output) &&
        !/\b(?:full|complete|final)\s+(?:solution|implementation|code)\b/i.test(output);
    case "stronger_hint":
      return /\b(?:trace|data flow|constraint|boundary|interface|input|output|partial skeleton)\b/i.test(output) &&
        /\b(?:invariant|edge case|failure|reject|preserve)\b/i.test(output);
    case "quiz_shape":
      return (output.match(/^\s*[ABC][).:-]\s+.+$/gm) || []).length === 3 &&
        /\[correct-option:\s*[ABC]\]/i.test(output);
    case "quiz_grounding": {
      const position = output.match(/\[correct-option:\s*([ABC])\]/i)?.[1];
      const selected = position
        ? output.match(new RegExp(`^\\s*${position}[).:-]\\s+(.+)$`, "mi"))?.[1] || ""
        : "";
      return /\b(?:payment|idempot|duplicate|retry|charge)\b/i.test(output) &&
        /\b(?:reject duplicate|reuse (?:the )?(?:prior|same) result|idempotency key)\b/i.test(selected);
    }
    case "quiz_variation":
      return /\[correct-option:\s*[ABC]\]/i.test(output);
    case "phase_fit":
      if (testCase.id === "learner-owned-refusal") {
        return !/\bown words\b|\bexplain(?: the)? (?:decision|approach)\b/i.test(output);
      }
      if (testCase.id === "explain-it-back-required") {
        return /\b(?:decision|approach|failure|break|invariant)\b/i.test(output);
      }
      return /\b(?:hint|look|trace|locate|start|invariant|interface|caller|edge case)\b/i.test(output) &&
        !/\bown words\b/i.test(output);
    case "concise":
      return output.trim().split(/\s+/).filter(Boolean).length <= 220;
    default:
      throw new Error(`Unknown teaching check: ${check}`);
  }
}

for (const testCase of cases) {
  for (let sample = 1; sample <= samples; sample += 1) {
    const prompt = `${skill}\n\nEvaluate this scenario as DuckTutor. Respond to the developer, not to this evaluator.\n\n${testCase.scenario}\n`;
    const result = spawnSync(command, {
      cwd: root,
      encoding: "utf8",
      input: prompt,
      maxBuffer: 1024 * 1024,
      shell: true,
    });
    if (result.status !== 0) {
      failures += 1;
      process.stderr.write(`FAIL ${testCase.id} sample ${sample}: runner exited ${result.status}\n${result.stderr || ""}`);
      continue;
    }
    const failedChecks = testCase.checks.filter((check) => !grade(check, result.stdout, testCase));
    if (failedChecks.length) {
      failures += 1;
      process.stderr.write(`FAIL ${testCase.id} sample ${sample}: ${failedChecks.join(", ")}\n`);
    } else {
      process.stdout.write(`PASS ${testCase.id} sample ${sample}\n`);
      if (testCase.checks.includes("quiz_variation")) {
        const position = result.stdout.match(/\[correct-option:\s*([ABC])\]/i)?.[1].toUpperCase();
        if (position) {
          if (!quizPositions.has(testCase.id)) quizPositions.set(testCase.id, new Set());
          quizPositions.get(testCase.id).add(position);
        }
      }
    }
  }
}

if (samples > 1) {
  for (const testCase of cases.filter((entry) => entry.checks.includes("quiz_variation"))) {
    if ((quizPositions.get(testCase.id)?.size || 0) < 2) {
      failures += 1;
      process.stderr.write(`FAIL ${testCase.id}: correct option position did not vary across samples\n`);
    }
  }
}

if (failures) {
  process.stderr.write(`${failures} teaching eval(s) failed\n`);
  process.exit(1);
}
process.stdout.write("All teaching evals passed\n");
