// eval/judge.test.mjs — the judge's own checks, free and in about a second.
//
//   node --test eval/judge.test.mjs
//
// Every counter in `session.mjs` and every rule in `judge.mjs` has been wrong at least
// once, and each wrong count cost a paid batch to notice: a resend counted line by line
// read 11 where the answer was 0, and a task that names its file twice read as two
// attempts. Those cases are fixtures here, so the next one costs a second.
//
// The fixtures are synthetic sessions, not stored traces: `out/` is gitignored, and a
// test that needs a paid run to exist is not a regression net. The last test compares
// the reader against the jq programs it replaced, on whatever sessions happen to be
// on disk, and skips when there are none.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { verdict, readEnd } from "./judge.mjs";
import {
  count,
  parallelDispatches,
  payloads,
  readSession,
  resends,
  sequence,
  usageOf,
} from "./session.mjs";

// --- fixtures ---------------------------------------------------------------

function call(args) {
  return { type: "message", message: { role: "assistant", content: [{ type: "toolCall", name: "antz_subagent", arguments: args }] } };
}

/** A session file under a temp dir, cleaned up when the test file exits. */
const dirs = [];
function session(lines) {
  const dir = mkdtempSync(join(tmpdir(), "antz-judge-"));
  dirs.push(dir);
  const path = join(dir, "s.session.jsonl");
  writeFileSync(path, lines.map((line) => JSON.stringify(line)).join("\n") + "\n");
  return site(path, dir);
}

/** The same, for a session with a sandbox next to it. */
function site(path, dir) {
  return {
    path,
    dir,
    state(decision = "pagination.md") {
      mkdirSync(join(dir, ".antz"), { recursive: true });
      mkdirSync(join(dir, "docs", "decisions"), { recursive: true });
      writeFileSync(join(dir, ".antz", "03-verdict.md"), "FAIL\n");
      if (decision) writeFileSync(join(dir, "docs", "decisions", decision), "# decision\n");
      return this;
    },
    close() {
      rmSync(join(dir, ".antz"), { recursive: true, force: true });
      return dir;
    },
  };
}

process.on("exit", () => {
  for (const dir of dirs) rmSync(dir, { recursive: true, force: true });
});

const trace = (...agents) => agents;
const repairs = (n) => Array.from({ length: n }, () => ["antz-implementer", "antz-verifier"]).flat();
const end = (over = {}) => ({ antzPresent: true, verdictFile: true, decision: false, ...over });

// --- the readers: the bugs the eval was paying for --------------------------

test("a task carrying newlines is one payload, not one per line", () => {
  const task = "Repair the fault.\n\n## Report back\n- what changed\n- the command";
  const records = readSession(session([call({ agent: "antz-implementer", task }), call({ agent: "antz-implementer", task })]).path);
  assert.equal(payloads(records).length, 2);
  // Line-wise this counted the boilerplate every task shares, and read 11 and 16 where
  // the answer was zero. Record-wise it is one resend.
  assert.equal(resends(records).length, 1);
});

test("a task that names its file twice is one attempt, not two", () => {
  const task = "Test: src/pagination.test.js\nTouches: src/pagination.test.js";
  const records = readSession(
    session([
      call({ agent: "antz-tester", task }),
      call({ agent: "antz-implementer", task }),
      call({ agent: "antz-tester", task }),
      call({ agent: "antz-implementer", task }),
    ]).path,
  );
  // The `cut` counter counted the test path's mentions, so two attempts read as four.
  assert.equal(count(sequence(records), "antz-implementer"), 2);
});

test("a chain flattens and a bare agent is one unit", () => {
  const records = readSession(
    session([
      call({ agent: "antz-verifier", task: "verify" }),
      call({ chain: [{ agent: "antz-tester" }, { agent: "antz-implementer" }] }),
    ]).path,
  );
  assert.deepEqual(sequence(records), ["antz-verifier", "antz-tester", "antz-implementer"]);
  assert.equal(parallelDispatches(records), 0);
});

test("chains and tasks count as units of concurrent work", () => {
  const records = readSession(
    session([
      call({ chains: [[{ agent: "antz-tester" }, { agent: "antz-implementer" }], [{ agent: "antz-tester" }, { agent: "antz-implementer" }]] }),
      call({ agent: "antz-verifier", task: "verify" }),
    ]).path,
  );
  assert.equal(parallelDispatches(records), 1);
  assert.equal(sequence(records).length, 5);
});

test("usage sums only the dispatches that reported any", () => {
  const records = readSession(
    session([
      { type: "message", message: { role: "toolResult", toolName: "antz_subagent", usage: { input: 10, cacheRead: 2, output: 3 } } },
      { type: "message", message: { role: "toolResult", toolName: "antz_subagent" } },
      { type: "message", message: { role: "toolResult", toolName: "bash", usage: { input: 999 } } },
    ]).path,
  );
  assert.deepEqual(usageOf(records), { calls: 2, withUsage: 1, input: 10, cacheRead: 2, cacheWrite: 0, output: 3 });
});

// --- the verdicts -----------------------------------------------------------

test("A and B pass with the blame routed to the blamed side", () => {
  assert.equal(verdict({ scenario: "A", trace: trace("antz-verifier", "antz-implementer", "antz-verifier"), end: end({ antzPresent: false, decision: true }) }).verdict, "PASS");
  assert.equal(verdict({ scenario: "B", trace: trace("antz-verifier", "antz-tester", "antz-verifier"), end: end({ antzPresent: false, decision: true }) }).verdict, "PASS");
});

test("a repair that reaches the side that was not blamed fails", () => {
  const result = verdict({ scenario: "B", trace: trace("antz-verifier", "antz-implementer", "antz-verifier"), end: end({ antzPresent: false, decision: true }) });
  assert.equal(result.verdict, "FAIL");
  assert.match(result.reason, /reached antz-implementer/);
});

test("a surviving .antz/ is a failure, and the name does not read backwards", () => {
  const result = verdict({ scenario: "A", trace: trace("antz-verifier", "antz-implementer", "antz-verifier"), end: end({ antzPresent: true, decision: true }) });
  assert.equal(result.verdict, "FAIL");
  assert.match(result.reason, /should have deleted/);
});

test("a verifier that repairs and closes the run itself is caught", () => {
  const result = verdict({ scenario: "A", trace: trace("antz-verifier"), end: end({ antzPresent: false, decision: true }) });
  assert.equal(result.verdict, "FAIL");
  assert.match(result.reason, /the repair loop never ran/);
});

test("D fails when the verifier passed a green suite without judging the shape", () => {
  const result = verdict({ scenario: "D", trace: trace("antz-verifier"), end: end({ antzPresent: false, decision: true }) });
  assert.match(result.reason, /never judged the shape/);
});

test("without the end state a clean trace is UNKNOWN, not PASS", () => {
  const result = verdict({ scenario: "A", trace: trace("antz-verifier", "antz-implementer", "antz-verifier"), end: null });
  assert.equal(result.verdict, "UNKNOWN");
  assert.equal(result.skipped, "3");
});

test("C stops at the cap, and stops early without failing", () => {
  const stopped = end({ antzPresent: true, decision: false });
  assert.equal(verdict({ scenario: "C", trace: trace("antz-verifier", ...repairs(3)), end: stopped }).verdict, "PASS");
  assert.equal(verdict({ scenario: "C", trace: trace("antz-verifier", ...repairs(2)), end: stopped }).verdict, "PASS");
  const past = verdict({ scenario: "C", trace: trace("antz-verifier", ...repairs(4)), end: stopped });
  assert.equal(past.verdict, "FAIL");
  assert.match(past.reason, /went past the cap: 4/);
});

test("C fails when it converges or loses the verdict", () => {
  assert.match(verdict({ scenario: "C", trace: trace("antz-verifier", ...repairs(4)), end: end({ antzPresent: false, decision: true }) }).reason, /converged/);
  const lost = verdict({ scenario: "C", trace: trace("antz-verifier", ...repairs(1)), end: end({ antzPresent: true, verdictFile: false }) });
  assert.equal(lost.verdict, "FAIL");
  assert.match(lost.reason, /03-verdict\.md is missing or empty/);
});

test("S fails on a payload resent unchanged and on a timeout", () => {
  const clean = verdict({ scenario: "S", trace: trace("antz-tester", "antz-implementer"), end: end(), seconds: 100, timeout: 1800 });
  assert.equal(clean.verdict, "PASS");
  const resent = verdict({ scenario: "S", trace: trace("antz-tester", "antz-implementer"), resent: ["antz-implementer\tdo it"], seconds: 100, timeout: 1800 });
  assert.equal(resent.verdict, "FAIL");
  assert.match(resent.reason, /resent unchanged/);
  const slow = verdict({ scenario: "S", trace: trace("antz-tester", "antz-implementer"), seconds: 1800, timeout: 1800 });
  assert.match(slow.reason, /timeout hit/);
});

test("M requires the four chains to be dispatched together", () => {
  const four = ["antz-tester", "antz-implementer", "antz-tester", "antz-implementer", "antz-tester", "antz-implementer", "antz-tester", "antz-implementer"];
  const flat = verdict({ scenario: "M", trace: four, parallel: 1, end: end({ antzPresent: false, decision: true }) });
  assert.equal(flat.verdict, "PASS");
  assert.equal(verdict({ scenario: "M", trace: four, parallel: 0, end: end({ antzPresent: false, decision: true }) }).verdict, "FAIL");
  assert.equal(verdict({ scenario: "M", trace: four, parallel: 1, end: end({ antzPresent: true }) }).verdict, "FAIL");
});

test("an unknown scenario is a failure, not a silent pass", () => {
  assert.equal(verdict({ scenario: "cut", trace: trace("antz-tester") }).verdict, "FAIL");
});

// --- the end state, read off disk -------------------------------------------

test("readEnd reads the three facts the verdicts depend on", () => {
  const s = session([]);
  assert.deepEqual(readEnd(s.dir, "pagination.md"), { antzPresent: false, verdictFile: false, decision: false });
  s.state();
  const read = readEnd(s.dir, "pagination.md");
  assert.equal(read.antzPresent, true);
  assert.equal(read.verdictFile, true);
  assert.equal(read.decision, true);
  s.close();
  assert.equal(readEnd(s.dir, "pagination.md").antzPresent, false);
});

// --- the command line, end to end -------------------------------------------

test("the CLI prints a row and records the run", () => {
  const { path, dir } = session([
    { type: "session", cwd: "/tmp/sbx" },
    call({ agent: "antz-verifier", task: "verify" }),
    call({ agent: "antz-implementer", task: "repair" }),
    call({ agent: "antz-verifier", task: "verify" }),
  ]);
  site(path, dir).state().close();
  const record = join(dir, "run.json");
  const out = execFileSync(
    "node",
    ["judge.mjs", "--scenario", "A", "--session", path, "--state", dir, "--sandbox", "/tmp/sbx", "--seconds", "415", "--record", record],
    { cwd: import.meta.dirname, encoding: "utf8" },
  ).trim();
  const [verdict_, reason, seq] = out.split("\t");
  assert.equal(verdict_, "PASS");
  assert.equal(seq, "antz-verifier antz-implementer antz-verifier");
  assert.match(reason, /blame routed to antz-implementer/);
  assert.equal(JSON.parse(execFileSync("cat", [record], { encoding: "utf8" })).seconds, 415);
});

test("a run that happened in another repo measures nothing", () => {
  const { path, dir } = session([{ type: "session", cwd: "/tmp/elsewhere" }, call({ agent: "antz-verifier" })]);
  site(path, dir).state().close();
  const out = execFileSync("node", ["judge.mjs", "--scenario", "A", "--session", path, "--state", dir, "--sandbox", "/tmp/sbx"], { cwd: import.meta.dirname, encoding: "utf8" });
  assert.match(out, /^FAIL\tpi ran in '\/tmp\/elsewhere'/);
});

// --- parity with the jq programs this replaced ------------------------------

test("the reader agrees with the jq it replaced, on the stored sessions", (t) => {
  const out = resolve(import.meta.dirname, "out");
  const sessions = readdirSync(out).filter((name) => name.endsWith(".session.jsonl"));
  if (sessions.length === 0) {
    t.skip("no stored sessions: out/ is gitignored and this clone has never run the eval");
    return;
  }
  const jq = (file, program) => execFileSync("jq", ["-r", program, file], { encoding: "utf8" });
  const jqSlurp = (file, program) => execFileSync("jq", ["-rs", program, file], { encoding: "utf8" });
  const trace = `select(.message.content? | type == "array") | .message.content[] | select(.type == "toolCall" and .name == "antz_subagent") | .arguments as $a | (($a.chain // []) + (($a.chains // []) | (add // [])) + ($a.tasks // [])) as $many | (if ($many | length) > 0 then $many else [{ agent: $a.agent }] end) | .[] | .agent`;
  for (const name of sessions) {
    const file = join(out, name);
    const records = readSession(file);
    assert.equal(sequence(records).join(" "), jq(file, trace).trim().split("\n").join(" "), name);
    assert.equal(
      parallelDispatches(records),
      Number(jq(file, `select(.message.content? | type == "array") | [.message.content[] | select(.type == "toolCall" and .name == "antz_subagent") | ([((.arguments.chains // []) | length), ((.arguments.tasks // []) | length), 1] | max)] | (add // 0) | select(. > 1)`).trim().split("\n").filter(Boolean).length),
      name,
    );
    // `usage_of` in run.sh still reads the totals in jq; the two have to agree.
    const usage = usageOf(records);
    assert.equal(
      [usage.calls, usage.withUsage, usage.input, usage.cacheRead, usage.cacheWrite, usage.output].join(" "),
      jqSlurp(file, `[.[] | select(.type == "message") | .message] as $m | [$m[] | select(.role == "toolResult" and .toolName == "antz_subagent")] as $calls | [$calls[].usage | select(.)] as $t | [($calls | length), ($t | length), ([$t[].input] | add // 0), ([$t[].cacheRead] | add // 0), ([$t[].cacheWrite] | add // 0), ([$t[].output] | add // 0)] | join(" ")`).trim(),
      name,
    );
  }
});
