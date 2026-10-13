// Reading a pi session, as plain functions.
//
// The trace of a run is the sequence of `antz_subagent` dispatches, and the cost is
// the `usage` pi persists on each `toolResult`. Both live in the session jsonl and
// nothing else does — the same session is what `run.sh` judges, `agents.sh` reports
// and `rejudge.sh` re-reads, so the extraction lives here once instead of in four
// jq programs.
//
// Pure: a path in, values out. No side effects, so the verdicts it feeds can be
// tested against stored traces for free. This is what the verdict needs and no more:
// `agents.sh` still reads the same file in jq for the per-agent table, which is why
// `judge.test.mjs` compares the two readers on the sessions on disk.
import { readFileSync } from "node:fs";

export const DISPATCH_TOOL = "antz_subagent";

/** The session as records. One JSON object per line; a blank line is skipped. */
export function readSession(path) {
  return readFileSync(path, "utf8")
    .split("\n")
    .filter((line) => line.trim() !== "")
    .map((line) => JSON.parse(line));
}

/** Every `antz_subagent` call, in order, with the arguments it was given. */
export function dispatches(records) {
  const calls = [];
  for (const record of records) {
    const content = record.message?.content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (part?.type === "toolCall" && part.name === DISPATCH_TOOL) {
        calls.push(part.arguments ?? {});
      }
    }
  }
  return calls;
}

/**
 * The units of work one dispatch carried. A `chain` and a `tasks` list flatten to
 * their elements; `chains` is a list of chains, so it flattens twice — which is the
 * whole point of the shape: one call, several independent units. A dispatch written
 * as a bare `agent` is one unit.
 */
export function units(args) {
  const many = [
    ...asArray(args.chain),
    ...asArray(args.chains).flatMap(asArray),
    ...asArray(args.tasks),
  ];
  return many.length > 0 ? many : [{ agent: args.agent, task: args.task }];
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

/** The trace the eval measures: which agent ran, in the order it was dispatched. */
export function sequence(records) {
  return dispatches(records).flatMap(units).map((unit) => String(unit?.agent ?? "null"));
}

/**
 * Every unit of work as `{ agent, task }`. `{previous}` is left literal: it is
 * substituted when the step runs, so two identical records mean the same task went
 * out twice with nothing changed — which is what the flow forbids for a task an
 * agent stopped on. The task may carry newlines, which is why a resend is decided
 * on the whole record and never on a line of it.
 */
export function payloads(records) {
  return dispatches(records)
    .flatMap(units)
    .filter((unit) => unit?.agent)
    .map((unit) => ({ agent: unit.agent, task: unit.task ?? "" }));
}

/** How many payloads were dispatched twice, byte for byte, and which. */
export function resends(records) {
  const seen = new Map();
  for (const payload of payloads(records)) {
    const key = `${payload.agent}\t${payload.task}`;
    seen.set(key, (seen.get(key) ?? 0) + 1);
  }
  return [...seen].filter(([, times]) => times > 1).map(([key]) => key);
}

/** Occurrences of one agent in a trace. */
export function count(trace, agent) {
  return trace.filter((name) => name === agent).length;
}

/**
 * How many dispatches carried more than one unit of concurrent work. Sibling calls
 * in one message count together, because pi runs those concurrently as well; a
 * dispatch of one unit is sequential by definition and does not count.
 */
export function parallelDispatches(records) {
  let parallel = 0;
  for (const record of records) {
    const content = record.message?.content;
    if (!Array.isArray(content)) continue;
    let live = 0;
    for (const part of content) {
      if (part?.type !== "toolCall" || part.name !== DISPATCH_TOOL) continue;
      const args = part.arguments ?? {};
      live += Math.max(asArray(args.chains).length, asArray(args.tasks).length, 1);
    }
    if (live > 1) parallel++;
  }
  return parallel;
}

/**
 * What the subagents spent in one session: token counts only. `calls` is every
 * dispatch and `withUsage` is how many reported any, so a provider that reports
 * nothing shows up as calls > 0 with every token column at zero.
 */
export function usageOf(records) {
  const calls = records
    .map((record) => record.message)
    .filter((m) => m?.role === "toolResult" && m.toolName === DISPATCH_TOOL);
  const tokens = calls.map((call) => call.usage).filter(Boolean);
  const sum = (key) => tokens.reduce((total, usage) => total + number(usage[key]), 0);
  return {
    calls: calls.length,
    withUsage: tokens.length,
    input: sum("input"),
    cacheRead: sum("cacheRead"),
    cacheWrite: sum("cacheWrite"),
    output: sum("output"),
  };
}

function number(value) {
  return typeof value === "number" ? value : 0;
}

/** The directory the run says it happened in. The harness checks it is the sandbox. */
export function sessionCwd(records) {
  return records.find((record) => record.type === "session")?.cwd ?? "";
}
