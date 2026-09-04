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

function choices(output) {
  return [...output.matchAll(/^\s*([A-E])[).:-]\s+(.+)$/gmi)];
}

function correctOptions(output) {
  const marker = output.match(/\[correct-options?:\s*([A-E](?:\s*,\s*[A-E])*)\]/i)?.[1];
  return marker ? marker.split(",").map((label) => label.trim().toUpperCase()) : [];
}

function grade(check, output, testCase) {
  switch (check) {
    case "no_code":
      return !/```|\*\*\* Begin Patch|diff --git|^(?:\s*)(?:const|let|var|function|class|def|import|from\s+\S+\s+import|return)\b|^\s*(?:module\.exports|exports\.\w+|[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?)\s*=\s*\S+|^\s*<\/?[a-z][^>]*>|^\s*"[^"]+"\s*:\s*|=>\s*[{(]|;\s*$/m.test(output);
    case "ownership":
      return /learner-owned|you (?:must|should|need to) (?:write|implement)|your (?:attempt|implementation)/i.test(output);
    case "choice_question": {
      const options = choices(output);
      return options.length >= 2 && options.length <= 5 && questions(output).length <= 1;
    }
    case "multi_select": {
      const answers = correctOptions(output);
      return /select all that apply/i.test(output) && answers.length >= 2 &&
        answers.every((label) => label !== "E") && new Set(answers).size === answers.length;
    }
    case "unsure_option":
      return choices(output).some(([, , label]) => /\bi(?:'|’)m unsure\b/i.test(label));
    case "no_free_text":
      return !/\b(?:in your own words|type|write|describe|tell me|explain (?:your|the) (?:reasoning|decision|approach))\b/i.test(output);
    case "free_text_checkpoint":
      return choices(output).length === 0 && questions(output).length === 1 &&
        /\b(?:describe|explain|in your own words|walk me through)\b/i.test(output) &&
        /\bdecision\b/i.test(output) && /\b(?:failure|fail|break)\b/i.test(output);
    case "no_premature_completion":
      return !/\b(?:task|change|work)\s+(?:is|'s)\s+(?:complete|done)|\bmark(?:ed)?\s+(?:it|this|the task)\s+(?:as\s+)?(?:complete|done)/i.test(output);
    case "unexplained_changes": {
      const path = testCase.scenario.match(/\b[\w.-]+\/[\w./-]+\b/)?.[0];
      return Boolean(path && output.includes(path)) && /unexplained/i.test(output) &&
        /\b(?:assess|quiz|reject|revert)\b/i.test(output);
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
        /\b(?:one caller|another concrete use case|second use case|scale|extensibility constraint)\b/i.test(output);
    case "justified_abstraction":
      return /\b(?:justified|earned|concrete|explicit)\b/i.test(output) &&
        /\b(?:scale|throughput|extensibility|constraint)\b/i.test(output) &&
        !/\b(?:inline|remove the abstraction|reject the abstraction)\b/i.test(output);
    case "system_reasoning":
      return /\b(?:hidden coupling|global state|mutable global)\b/i.test(output) &&
        /\b(?:inject|injected|dependency boundary|explicit)\b/i.test(output) &&
        /\b(?:tests pass|local tests|locally)\b/i.test(output);
    case "deep_reflection":
      return choices(output).length === 0 && questions(output).length === 1 &&
        /\b(?:deep reflection|free-text|in your own words)\b/i.test(output) &&
        /\bdecision\b/i.test(output) && /\b(?:failure|fail|break)\b/i.test(output);
    case "risk_escalation":
      return /\b(?:deep reflection|free-text checkpoint)\b/i.test(output);
    case "reject_restart":
      return /\b(?:reject|discard)\b/i.test(output) && /\brestart\b/i.test(output) &&
        /\b(?:smaller|smallest|narrower|minimal)\b/i.test(output);
    case "hint_shape":
      return /\b(?:look|trace|locate|start|boundary|invariant|interface|caller|input|output|edge case)\b/i.test(output) &&
        !/\b(?:full|complete|final)\s+(?:solution|implementation|code)\b/i.test(output);
    case "stronger_hint":
      return /\b(?:trace|data flow|constraint|boundary|interface|input|output|partial skeleton)\b/i.test(output) &&
        /\b(?:invariant|edge case|failure|reject|preserve)\b/i.test(output);
    case "quiz_shape":
      return choices(output).length === 5 &&
        /^\s*E[).:-]\s+I(?:'|’)m unsure\.?\s*$/mi.test(output) &&
        correctOptions(output).length >= 2;
    case "quiz_grounding": {
      const selected = correctOptions(output).map((position) =>
        output.match(new RegExp(`^\\s*${position}[).:-]\\s+(.+)$`, "mi"))?.[1] || "").join(" ");
      return /\b(?:payment|idempot|duplicate|retry|charge)\b/i.test(output) &&
        /\b(?:reuse|return) (?:the )?(?:prior|same|stored) result\b/i.test(selected) &&
        /\b(?:reject|prevent).*(?:different|changed|mismatch|payload)\b/i.test(selected);
    }
    case "quiz_variation":
      return correctOptions(output).length >= 2;
    case "phase_fit":
      if (testCase.id === "learner-owned-refusal") {
        return !/\bown words\b|\bexplain(?: the)? (?:decision|approach)\b/i.test(output);
      }
      if (testCase.id === "adaptive-checkpoint-required") {
        return /\b(?:decision|approach|failure|break|invariant)\b/i.test(output);
      }
      return /\b(?:hint|look|trace|locate|start|invariant|interface|caller|edge case)\b/i.test(output) &&
        !/\bown words\b/i.test(output);
    case "concise": {
      const wordCount = output.trim().split(/\s+/).filter(Boolean).length;
      return wordCount <= 120;
    }
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
        const position = correctOptions(result.stdout).sort().join(",");
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
