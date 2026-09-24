// The dispatch tool's own checks. Not part of pi, not installed, not a flow test:
// this drives extensions/antz-subagent.ts directly, with the pi SDK stubbed, so
// the four shapes, the concurrency cap, the per-chain handoff, the failure path
// and the two renderers can be asserted on for free and in about a second.
//
//   eval/dispatch.sh          # sets up stubs and the copy under test, runs this
//
// The fake agents are the input each block varies: they sleep for a fixed delay,
// record the prompt they got, answer with a marker the checks can look for, and
// can be told to fail on one task. Everything else — the fan-out, the ordering,
// the `{previous}` substitution, the capping, the labels — is the tool's.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import antz from "./antz-subagent.ts";

const AGENTS = ["antz-tester", "antz-implementer"];
const FIXTURES = mkdtempSync(join(tmpdir(), "antz-dispatch-"));
process.on("exit", () => rmSync(FIXTURES, { recursive: true, force: true }));
for (const name of AGENTS) {
  mkdirSync(join(FIXTURES, ".pi", "agents"), { recursive: true });
  writeFileSync(
    join(FIXTURES, ".pi", "agents", `${name}.md`),
    `---\nname: ${name}\ndescription: fixture ${name}\ntools: read\n---\n\nBODY-${name}\n`,
  );
}

let tool;
antz({
  on() {},
  getActiveTools: () => [],
  setActiveTools() {},
  registerTool: (definition) => (tool = definition),
});

// What the fake agents do. `delay` and `failOn` are per block; `prompts` is the
// record of what each of them was handed; `live` is peaked in prompt() and
// released in dispose(), which is the same window the real tool holds a session
// for — so maxLive is what proves the concurrency cap rather than the wall clock.
let spawn = 0;
let live = 0;
let maxLive = 0;
const prompts = [];

globalThis.__mkSession = async () => {
  // One listener per session, because a run reads only the tool events its own
  // child emitted. `__read` is the file the fake child reads, which is how a
  // skills block makes the run look like the model loading a SKILL.md.
  let listener;
  const session = {
    messages: [],
    agent: { state: { model: { provider: "fixture", id: "model" }, thinkingLevel: "medium" } },
    subscribe: (fn) => {
      listener = fn;
      return () => (listener = undefined);
    },
    abort() {},
    dispose() {
      live--;
    },
    getSessionStats: () => ({
      tokens: { input: 1, output: 2, cacheRead: 0, cacheWrite: 0, total: 3 },
      cost: 0.001,
    }),
    async prompt(text) {
      spawn++;
      live++;
      maxLive = Math.max(maxLive, live);
      await new Promise((resolve) => setTimeout(resolve, globalThis.__delay));
      if (globalThis.__failOn && text.includes(globalThis.__failOn)) throw new Error("boom");
      if (globalThis.__read) {
        const args = { path: globalThis.__read };
        listener?.({ type: "tool_execution_start", toolCallId: "read-1", toolName: "read", args });
        listener?.({ type: "tool_execution_end", toolCallId: "read-1", toolName: "read", isError: false });
      }
      prompts.push(text);
      const task = text.split("TASK:").pop().trim().split("\n", 1)[0];
      session.messages.push({ role: "assistant", content: [{ type: "text", text: `OUT[${task}]` }] });
    },
  };
  return { session };
};

function reset({ delay = 200, failOn, read } = {}) {
  spawn = 0;
  live = 0;
  maxLive = 0;
  prompts.length = 0;
  globalThis.__delay = delay;
  globalThis.__failOn = failOn;
  globalThis.__read = read;
}

const dispatch = (params) =>
  tool.execute("check", params, undefined, undefined, { cwd: FIXTURES, model: undefined, thinkingLevel: undefined });

const theme = { fg: (_color, text) => text, bold: (text) => text };
const renderCall = (args) => tool.renderCall(args, theme, { lastComponent: undefined, argsComplete: true }).content;
const renderResult = (result, expanded = false) =>
  tool.renderResult(result, { expanded }, theme, { lastComponent: undefined }).content;

let failed = 0;
function check(name, ok, detail = "") {
  if (!ok) failed++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? `  ${detail}` : ""}`);
}

const pair = (task) => [
  { agent: "antz-tester", task: `TASK: ${task}-test` },
  { agent: "antz-implementer", task: `TASK: ${task}-code {previous}` },
];

console.log("== chains: parallel, one chain per task");
reset();
const four = await dispatch({ chains: [1, 2, 3, 4].map((n) => pair(`t${n}`)) });
check("four chains of two steps spawn eight agents", spawn === 8, `spawn=${spawn}`);
check("all eight finished", four.details.runs.every((run) => run.status === "done") && !four.isError);
check("mode and run count", four.details.mode === "chains" && four.details.runs.length === 8);
check("one output block per chain, not per agent", four.content[0].text.split("---").length === 4);
check("runs are numbered chain.step", four.details.runs[1].group === 0 && four.details.runs[1].step === 1);
check("last run is chain 4 step 2", four.details.runs[7].group === 3 && four.details.runs[7].step === 1);
check("an implementer carries its own tester's report", four.details.runs[5].task.includes("OUT[t3-test]"), JSON.stringify(four.details.runs[5].task));
check("no chain sees another chain's report", !four.details.runs[5].task.includes("OUT[t1-test]"));
check("nested usage is summed", four.usage.totalTokens === 24, `totalTokens=${four.usage.totalTokens}`);

console.log("\n== the cap: never more than four agents in flight");
reset({ delay: 50 });
const six = await dispatch({ chains: [1, 2, 3, 4, 5, 6].map((n) => pair(`c${n}`)) });
check("six chains, twelve agents, all of them ran", spawn === 12, `spawn=${spawn}`);
check("peak concurrency was the cap", maxLive === 4, `peak=${maxLive}`);
check("every chain finished", six.details.runs.every((run) => run.status === "done"));

console.log("\n== a chain that fails");
reset({ failOn: "t2-code" });
const broken = await dispatch({ chains: [1, 2, 3].map((n) => [...pair(`t${n}`), { agent: "antz-tester", task: `TASK: ${n}-retest` }]) });
check("the failure is reported", broken.isError === true);
check("sibling chains still completed", broken.details.runs.filter((run) => run.status === "done").length === 7);
check(
  "the step behind it says not run instead of staying queued",
  broken.details.runs[5].status === "failed" && /not run:/.test(broken.details.runs[5].error ?? ""),
  broken.details.runs[5].error,
);
check("only the failed chain is labelled FAILED", broken.content[0].text.split("---").filter((block) => /FAILED/.test(block)).length === 1);

console.log("\n== the shapes are exclusive");
let rejected = "";
try {
  await dispatch({ tasks: [{ agent: "antz-tester", task: "TASK: x" }], chains: [[{ agent: "antz-tester", task: "TASK: y" }]] });
} catch (error) {
  rejected = String(error.message);
}
check("two shapes in one call is refused", /exactly one of/.test(rejected), rejected);
let empty = "";
try {
  await dispatch({ task: "TASK: orphan" });
} catch (error) {
  empty = String(error.message);
}
check("a call with no shape is refused", /exactly one of/.test(empty), empty);

console.log("\n== the older three still behave");
reset();
const tasks = await dispatch({
  tasks: [
    { agent: "antz-tester", task: "TASK: a" },
    { agent: "antz-tester", task: "TASK: b" },
  ],
});
check("tasks is parallel and flat", tasks.details.mode === "tasks" && tasks.details.runs.every((run) => run.group === undefined));
reset();
const chain = await dispatch({
  chain: [
    { agent: "antz-tester", task: "TASK: c" },
    { agent: "antz-implementer", task: "TASK: d {previous}" },
  ],
});
check("chain is sequential with the handoff", /OUT\[c\]/.test(chain.details.runs[1].task));
reset();
const single = await dispatch({ agent: "antz-tester", task: "TASK: e" });
check("single works", single.details.mode === "single" && single.details.runs[0].status === "done");
reset({ delay: 50 });
const soloChain = await dispatch({ chains: [[{ agent: "antz-tester", task: "TASK: solo" }]] });
check("a chains call of one chain works", soloChain.details.runs.length === 1 && soloChain.details.runs[0].status === "done");

console.log("\n== the skills a child is handed, and the one it reads");
const SKILL_FILE = join(FIXTURES, "skills", "antz-tdd", "SKILL.md");
globalThis.__skills = [{ name: "antz-tdd", filePath: SKILL_FILE }];
reset({ read: SKILL_FILE });
const skilled = await dispatch({ agent: "antz-tester", task: "TASK: skilled" });
check("the discovered skills are on the details, once per call", JSON.stringify(skilled.details.skills) === '["antz-tdd"]', JSON.stringify(skilled.details.skills));
check("reading the SKILL.md marks the skill as used", JSON.stringify(skilled.details.runs[0].skillsUsed) === '["antz-tdd"]', JSON.stringify(skilled.details.runs[0].skillsUsed));
check("the header names what was available", /skills: antz-tdd/.test(renderResult(skilled, true)));
check("the expanded row names what was used", /skills used: antz-tdd/.test(renderResult(skilled, true)));
reset({ read: "skills/antz-tdd/SKILL.md" });
const relative = await dispatch({ agent: "antz-tester", task: "TASK: relative" });
check("a relative read still resolves to the skill", JSON.stringify(relative.details.runs[0].skillsUsed) === '["antz-tdd"]', JSON.stringify(relative.details.runs[0].skillsUsed));
reset({ read: join(FIXTURES, "src", "pagination.js") });
const plain = await dispatch({ agent: "antz-tester", task: "TASK: plain" });
check("an ordinary read is not a skill", plain.details.runs[0].skillsUsed === undefined, JSON.stringify(plain.details.runs[0].skillsUsed));
check("available and used are not the same list", !/skills used:/.test(renderResult(plain, true)) && /skills: antz-tdd/.test(renderResult(plain, true)));
globalThis.__skills = Array.from({ length: 10 }, (_, i) => ({
  name: `s${i}`,
  filePath: join(FIXTURES, "skills", `s${i}`, "SKILL.md"),
}));
reset();
const many = await dispatch({ agent: "antz-tester", task: "TASK: many" });
check(
  "the header caps a long list and counts the rest",
  /skills: s0, .*s7 \+2 more/.test(renderResult(many, true)),
  renderResult(many, true).split("\n")[1],
);
globalThis.__skills = undefined;
reset();
const bare = await dispatch({ agent: "antz-tester", task: "TASK: bare" });
check("no skills discovered, no header line", !/skills:/.test(renderResult(bare, true)));

console.log("\n== the panel");
const call = renderCall({ chains: [1, 2].map((n) => pair(`t${n}`)) });
check("each chain is one line, agents joined", (call.match(/antz-tester → antz-implementer/g) ?? []).length === 2, JSON.stringify(call));
check("the placeholder is not shown before it is substituted", !call.includes("{previous}"));
check("the mode is named", /chains/.test(call));
const collapsed = renderResult(four);
check("collapsed rows are numbered chain.step", /1\.1 antz-tester/.test(collapsed) && /4\.2 antz-implementer/.test(collapsed));
check("the header carries mode, count and state", /chains \(8\)/.test(collapsed) && /8\/8 done/.test(collapsed));
check("expanded rows keep the same numbering", /1\.1 antz-tester/.test(renderResult(four, true)));
check("tasks keeps flat numbering", /1\. antz-tester/.test(renderResult(tasks)));
check("a single agent is not numbered", !/\d+\.\d* ?antz-tester/.test(renderResult(single)));
check("a one-chain call is not numbered", !/\d+\.\d/.test(renderResult(soloChain)));
// The panel is rendered while the arguments stream in, so it must survive shapes
// the schema would reject once they are complete.
let rendered = "";
try {
  rendered = [{ chains: [{}] }, { chains: [[{ agent: "a" }]] }, { chains: [] }, { chains: [[]] }]
    .map((args) => renderCall(args))
    .join("");
} catch (error) {
  rendered = `threw: ${error.message}`;
}
check("a half-streamed chains does not throw while rendering", !rendered.startsWith("threw:"), rendered);

console.log(failed === 0 ? `\nall checks passed` : `\n${failed} check(s) failed`);
process.exit(failed === 0 ? 0 : 1);
