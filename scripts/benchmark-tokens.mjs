#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const command = process.env.DUCKTUTOR_BENCHMARK_COMMAND;
const configuration = process.env.DUCKTUTOR_BENCHMARK_LABEL;
if (!command) {
  process.stderr.write("Set DUCKTUTOR_BENCHMARK_COMMAND to a model command that reads stdin.\n");
  process.exit(2);
}
if (!configuration?.trim()) {
  process.stderr.write("Set DUCKTUTOR_BENCHMARK_LABEL to the model and settings used.\n");
  process.exit(2);
}

const sampleFlag = process.argv.indexOf("--samples");
const samples = sampleFlag >= 0 ? Number(process.argv[sampleFlag + 1]) : 1;
if (!Number.isInteger(samples) || samples < 1 || samples > 8) {
  process.stderr.write("--samples must be an integer from 1 to 8.\n");
  process.exit(2);
}

const scenarios = [
  {
    id: "explain-approach",
    request: "A proposed fix changes `return total` to `return Math.round(total)` in an invoice calculator. Before accepting it, explain the approach in plain language and identify what must be understood or verified.",
  },
  {
    id: "diff-proportionality",
    request: "The request is to change the checkout button text from `Buy` to `Pay now`. The AI diff also renames six components, adds a button factory, and reformats eight files. Review whether the diff fits the problem.",
  },
  {
    id: "premature-abstraction",
    request: "A single receipt-email caller previously called `sendEmail(message)`. The proposed patch adds `MessageTransport`, `TransportFactory`, and `TransportRegistry`, but no second transport is planned. Review the design.",
  },
  {
    id: "reasoning-coupling",
    request: "A checkout formatting patch passes local tests, but the formatter now imports a private cache from the payment module and mutates its singleton state. Assess completion and system-level risk.",
  },
  {
    id: "understanding-over-output",
    request: "An AI-generated null-handling patch passes its tests, but the developer cannot explain which null cases are accepted or why the fallback is safe. Decide whether to accept it and state the next step.",
  },
];
const skill = fs.readFileSync(path.join(root, "skills/tutor/SKILL.md"), "utf8");
const failureExcerptLimit = 800;

process.on("uncaughtException", (error) => {
  process.stderr.write(`Error: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});

function approximateTokens(text) {
  return Math.ceil([...text].length / 4);
}

function failureExcerpt(value) {
  const detail = String(value || "").trim();
  if (!detail) return "";
  const excerpt = detail.slice(0, failureExcerptLimit);
  const suffix = detail.length > failureExcerptLimit ? "\n[stderr truncated]" : "";
  return `\n${excerpt}${suffix}`;
}

function failureOutput(result) {
  const streams = [
    result.stdout && `stdout: ${result.stdout.trim()}`,
    result.stderr && `stderr: ${result.stderr.trim()}`,
  ].filter(Boolean);
  return failureExcerpt(streams.join("\n"));
}

function run(prompt, scenario, mode, sample) {
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), "ducktutor-token-benchmark-"));
  try {
    const initialized = spawnSync("git", ["init", "-q"], { cwd: workspace, encoding: "utf8" });
    if (initialized.status !== 0) throw new Error(`could not initialize isolated Git repository: ${initialized.stderr}`);
    const result = spawnSync(command, {
      cwd: workspace,
      encoding: "utf8",
      input: prompt,
      maxBuffer: 1024 * 1024,
      shell: true,
    });
    if (result.status !== 0) {
      if (result.status === 127) {
        throw new Error(
          `${scenario} ${mode} sample ${sample} could not resolve its command in non-interactive /bin/sh. ` +
          "Shell aliases and functions are unavailable; use the underlying executable with its environment variables, or a wrapper script on PATH." +
          failureOutput(result),
        );
      }
      throw new Error(`${scenario} ${mode} sample ${sample} failed with exit ${result.status}.${failureOutput(result)}`);
    }
    return result.stdout;
  } finally {
    fs.rmSync(workspace, { recursive: true, force: true });
  }
}

function average(total) {
  return total / samples;
}

function display(value) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

function percentage(saved, baseline) {
  return baseline ? `${((saved / baseline) * 100).toFixed(1)}%` : "n/a";
}

const rows = scenarios.map((scenario) => {
  const responseOnly = "Do not use tools or edit files; return only response text.";
  const prompts = {
    baseline: `You are a helpful coding assistant. ${responseOnly}\n\n${scenario.request}\n`,
    DuckTutor: `${skill}\n\nRespond as DuckTutor. ${responseOnly}\n\n${scenario.request}\n`,
  };
  const modes = Object.fromEntries(Object.entries(prompts).map(([mode, prompt]) => [mode, {
    input: approximateTokens(prompt),
    outputTotal: 0,
  }]));
  for (let sample = 1; sample <= samples; sample += 1) {
    for (const [mode, prompt] of Object.entries(prompts)) {
      modes[mode].outputTotal += approximateTokens(run(prompt, scenario.id, mode, sample));
    }
  }
  const baselineInput = modes.baseline.input;
  const duckTutorInput = modes.DuckTutor.input;
  const baselineOutputAverage = average(modes.baseline.outputTotal);
  const duckTutorOutputAverage = average(modes.DuckTutor.outputTotal);
  const outputSaved = baselineOutputAverage - duckTutorOutputAverage;
  const inputOverhead = duckTutorInput - baselineInput;
  const netSaved = baselineInput + baselineOutputAverage - duckTutorInput - duckTutorOutputAverage;
  return {
    id: scenario.id,
    baselineOutputAverage,
    duckTutorOutputAverage,
    outputSaved,
    baselineInput,
    duckTutorInput,
    inputOverhead,
    netSaved,
    baselineOutputTotal: modes.baseline.outputTotal,
    duckTutorOutputTotal: modes.DuckTutor.outputTotal,
  };
});

const total = rows.reduce((sum, row) => {
  sum.baselineOutput += row.baselineOutputTotal;
  sum.duckTutorOutput += row.duckTutorOutputTotal;
  sum.baselineInput += row.baselineInput * samples;
  sum.duckTutorInput += row.duckTutorInput * samples;
  return sum;
}, { baselineOutput: 0, duckTutorOutput: 0, baselineInput: 0, duckTutorInput: 0 });
total.outputSaved = total.baselineOutput - total.duckTutorOutput;
total.inputOverhead = total.duckTutorInput - total.baselineInput;
total.netSaved = total.outputSaved - total.inputOverhead;

process.stdout.write(`Configuration: ${configuration}\n`);
process.stdout.write(`Method: ceil(characters / 4); ${scenarios.length} scenarios; ${samples} samples each.\n`);
process.stdout.write(`Model calls: ${scenarios.length * samples * 2} (${scenarios.length * samples} baseline + ${scenarios.length * samples} DuckTutor).\n`);
process.stdout.write("Input delta is DuckTutor prompt overhead (shared skill plus framing); command prompts, restored context, state, and hook messages are excluded.\n");
process.stdout.write("Approximation only; model tokenizers, caching, and responses vary. Negative savings mean added tokens.\n\n");
process.stdout.write("Per-pair averages:\n");
process.stdout.write("Scenario | Baseline output | DuckTutor output | Output saved | Baseline input | DuckTutor input | DuckTutor prompt overhead | Net saved\n");
for (const row of rows) {
  process.stdout.write(`${row.id} | ${display(row.baselineOutputAverage)} | ${display(row.duckTutorOutputAverage)} | ${display(row.outputSaved)} (${percentage(row.outputSaved, row.baselineOutputAverage)}) | ${row.baselineInput} | ${row.duckTutorInput} | ${row.inputOverhead} | ${display(row.netSaved)}\n`);
}
process.stdout.write("\nActual run totals:\n");
process.stdout.write("Scenario | Baseline output | DuckTutor output | Output saved | Baseline input | DuckTutor input | DuckTutor prompt overhead | Net saved\n");
process.stdout.write(`Aggregate | ${total.baselineOutput} | ${total.duckTutorOutput} | ${total.outputSaved} (${percentage(total.outputSaved, total.baselineOutput)}) | ${total.baselineInput} | ${total.duckTutorInput} | ${total.inputOverhead} | ${total.netSaved}\n`);
