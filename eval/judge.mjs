#!/usr/bin/env node
// eval/judge.mjs — the verdict for one run, as a pure function.
//
// `run.sh` produces a trace and an end state; this decides what they mean. It is
// separate from the run so the decision can be re-made for free: `rejudge.sh` points
// it at a stored session and the compact end state, and gets the same verdict without
// paying for a flow run. That is what makes a harness bug cost a second instead of a
// batch — every counter this file owns has been wrong at least once, and each wrong
// count cost a paid batch to notice.
//
//   judge.mjs --scenario A --session out/A-1.session.jsonl --state out/A-1.state \
//     --sandbox /tmp/antz-eval/A-1 --seconds 415 --timeout 1800
//
// Prints one tab-separated line: verdict, reason, trace, skipped checks. With
// `--state` the verdict is PASS or FAIL; without it the checks that read the end state
// are reported as skipped, and a run whose trace alone is clean comes back UNKNOWN
// rather than a PASS it cannot support.
import { existsSync, statSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import {
  count,
  parallelDispatches,
  readSession,
  resends,
  sequence,
  sessionCwd,
} from "./session.mjs";

const DECISION_OF = {
  A: "pagination.md",
  B: "pagination.md",
  C: "pagination.md",
  D: "pagination.md",
  S: "pagination.md",
  M: "collection-helpers.md",
  N: "store-helpers.md",
  H: "store-helpers.md",
};

/** The scenarios this judge knows a contract for. */
export const SCENARIOS = Object.keys(DECISION_OF);

/** What the run left behind. `antzPresent` is the one that reads backwards: `.antz/`
 *  survives only when the run did not close, because PASS deletes it. */
export function readEnd(dir, decision) {
  const antz = resolve(dir, ".antz");
  return {
    antzPresent: existsSync(antz),
    verdictFile: fileHasBytes(resolve(antz, "03-verdict.md")),
    decision: existsSync(resolve(dir, "docs", "decisions", decision)),
  };
}

function fileHasBytes(path) {
  try {
    return statSync(path).size > 0;
  } catch {
    return false;
  }
}

function oneLine(text) {
  return String(text).replace(/[\t\n]/g, " ").slice(0, 160);
}

/**
 * The checks, in the order `run.sh` applied them, as data: each either holds or is the
 * failure, and each names whether it needs the end state. A check skipped in trace-only
 * mode is skipped, not passed — that is the difference between "this run passed" and
 * "nothing here contradicts it".
 */
export function verdict({ scenario, trace, resent = [], parallel = 0, end = null, seconds, timeout }) {
  const seq = trace.length > 0 ? trace.join(" ") : "(no dispatches)";
  const reps = count(trace, "antz-implementer") + count(trace, "antz-tester");
  const checks = [];
  const state = (fail, reason) => checks.push({ needs: "state", fail, reason });
  const only = (fail, reason) => checks.push({ needs: "none", fail, reason });

  let pass = "";
  switch (scenario) {
    case "A":
    case "B":
    case "D": {
      const blame = scenario === "B" ? "antz-tester" : "antz-implementer";
      const other = scenario === "B" ? "antz-implementer" : "antz-tester";
      const blamed = count(trace, blame);
      const reruns = Math.max(
        0,
        count(trace.slice(trace.lastIndexOf(blame) + 1), "antz-verifier") - 1,
      );
      state(
        trace.length === 1 && trace[0] === "antz-verifier" && end?.decision && !end.antzPresent,
        scenario === "D"
          ? "the verifier read the green suite and passed: it never judged the shape"
          : "the verifier repaired and closed the run itself: the repair loop never ran",
      );
      only(trace[0] !== "antz-verifier", `the run did not open with a verification: '${seq}'`);
      only(
        count(trace, other) !== 0,
        `the repair reached ${other}, which was not blamed: '${seq}'`,
      );
      only(
        blamed < 1,
        scenario === "D"
          ? `the verifier did not reject the shape: nothing was repaired, got '${seq}'`
          : `nothing was repaired, so there was no blame to route: '${seq}'`,
      );
      only(
        trace[trace.length - 1] !== "antz-verifier",
        `the run did not close with a verification: '${seq}'`,
      );
      state(end?.antzPresent === true, "the verifier should have deleted .antz/ after PASS");
      state(
        end?.decision === false,
        `docs/decisions/${DECISION_OF[scenario]} is missing, and only PASS writes it`,
      );
      pass =
        scenario === "D"
          ? `the verifier failed the green change on shape, routed it to ${blame} (${blamed} round(s)), PASS: .antz/ deleted and the decision written`
          : `blame routed to ${blame} (${blamed} round(s)), PASS, .antz/ deleted and the decision written`;
      if (reruns > 0) {
        pass += `; the verifier needed ${reruns} extra round(s) to finish the PASS work`;
      }
      break;
    }
    case "C": {
      state(
        end?.decision === true || end?.antzPresent === false,
        "it converged: with the fault re-injected there can be no PASS",
      );
      only(reps > 3, `it went past the cap: ${reps} repairs`);
      only(reps < 1, `nothing was repaired, so no attempt could stop on the fault: '${seq}'`);
      only(trace[0] !== "antz-verifier", `the run did not enter at step 5: '${trace[0]}' ran first`);
      state(
        end?.verdictFile === false,
        ".antz/03-verdict.md is missing or empty: the verdict has to outlive the round",
      );
      pass =
        reps < 3
          ? `${reps} attempt(s) and an agent stopped on the unfixable fault`
          : `${reps} attempt(s), then it stopped`;
      pass += ": .antz/ untouched, no decision written";
      if (resent.length > 0) {
        pass += `; ${resent.length} payload(s) dispatched twice, which S is the scenario that forbids`;
      }
      break;
    }
    case "S": {
      only(
        resent.length > 0,
        `the stopped task was resent unchanged (${resent.length} payload(s)): ${oneLine(resent.join("\n"))}`,
      );
      checks.push({
        needs: "seconds",
        fail: seconds !== undefined && seconds >= timeout,
        reason:
          "it was still going when the timeout hit: the task outlasted the run instead of being cut",
      });
      only(
        trace[0] !== "antz-tester" || count(trace, "antz-implementer") < 1,
        `the task never reached the tester-to-implementer chain, so no agent could stop on it: '${seq}'`,
      );
      const ending = !end
        ? "end state not read"
        : !end.antzPresent || end.decision
          ? "closed in PASS anyway, .antz/ deleted and the decision written"
          : "left .antz/ in place and no decision written";
      pass = `no payload was dispatched twice: ${trace.length} dispatch(es), ${reps} repair(s) on the task, ${ending}`;
      break;
    }
    case "M":
    case "N":
    case "H": {
      state(end?.antzPresent === true, "the run did not finish: .antz/ is still there");
      state(end?.decision === false, `docs/decisions/${DECISION_OF[scenario]} is missing`);
      only(
        count(trace, "antz-tester") < 4 || count(trace, "antz-implementer") < 4,
        `the four planned tasks did not all reach the tester and the implementer: '${seq}'`,
      );
      only(
        parallel < 1,
        `the independent tasks were not dispatched together: no dispatch carried more than one unit of work: '${seq}'`,
      );
      pass = `four independent chains dispatched in parallel (${parallel} dispatch(es) carried more than one), verified: decision written and .antz/ deleted`;
      break;
    }
    default:
      return { verdict: "FAIL", reason: "unknown scenario", trace: seq, skipped: "" };
  }

  const failed = checks.find((check) => check.fail);
  const skipped = checks.filter((check) => check.needs === "state" && !end && !check.fail);
  if (failed) return { verdict: "FAIL", reason: failed.reason, trace: seq, skipped: "" };
  if (skipped.length > 0) {
    return {
      verdict: "UNKNOWN",
      reason: `the trace holds, but ${skipped.length} check(s) need the end state, which was not kept`,
      trace: seq,
      skipped: String(skipped.length),
    };
  }
  return { verdict: "PASS", reason: pass, trace: seq, skipped: "" };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  for (const required of ["scenario", "session"]) {
    if (args[required] === undefined) {
      process.stderr.write(`judge.mjs: --${required} is required\n`);
      process.exit(2);
    }
  }
  const records = readSession(args.session);
  const cwd = sessionCwd(records);
  const result = verdict({
    scenario: args.scenario,
    trace: sequence(records),
    resent: resends(records),
    parallel: parallelDispatches(records),
    end: args.state === undefined ? null : readEnd(args.state, DECISION_OF[args.scenario]),
    seconds: args.seconds,
    timeout: args.timeout,
  });

  // The run is meaningless if pi ran somewhere other than the sandbox: `/antz` routes
  // on the cwd, so another repo would be graded.
  if (args.sandbox !== undefined && cwd !== args.sandbox) {
    result.verdict = "FAIL";
    result.reason = `pi ran in '${cwd}' instead of the sandbox: the run measures nothing`;
  }

  process.stdout.write([result.verdict, result.reason, result.trace, result.skipped].join("\t") + "\n");

  if (args.record) {
    writeFileSync(
      args.record,
      JSON.stringify(
        {
          scenario: args.scenario,
          run: args.run,
          seconds: args.seconds,
          timeout: args.timeout,
          sandbox: args.sandbox ?? "",
          cwd,
          verdict: result.verdict,
          reason: result.reason,
        },
        null,
        2,
      ) + "\n",
    );
  }
}

function parseArgs(argv) {
  const args = { timeout: 1800 };
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i].replace(/^--/, "");
    const value = argv[i + 1];
    args[key] = key === "timeout" || key === "seconds" ? Number(value) : value;
  }
  return args;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) main();
