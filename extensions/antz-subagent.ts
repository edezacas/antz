// ~/.pi/agent/extensions/antz-subagent.ts
//
// antz's subagent tool, no third-party dependencies: every agent runs as its own
// AgentSession in this process through pi's SDK, never as a child `pi` process, so
// its `tools:` allowlist and `model:` pin are enforced by the SDK rather than by
// flags this file hopes `pi` still accepts.
//
// Each child gets the repo's skills, AGENTS.md and its declared tools, but no
// extensions: no recursion into this tool, no side effects from whatever else the
// session loaded. Its instructions ride in as the first user message, not the
// system prompt, so that prompt stays byte-identical across agents and the provider
// can reuse one cached prefix. Its usage is returned on the tool result, so pi
// totals it in the session (footer, `/session`, RPC).
//
// The panel is built from `details`, rendered and persisted but never sent to the
// model, while `content` — the part the orchestrator reads — stays capped.

import type { AgentSession, AgentToolResult, ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  CONFIG_DIR_NAME,
  createAgentSession,
  DefaultResourceLoader,
  getAgentDir,
  keyHint,
  ModelRuntime,
  parseFrontmatter,
  resolveCliModel,
  SessionManager,
} from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

const MAX_CONCURRENCY = 4;
const TOOL_NAME = "antz_subagent";
// How much of a child's final text reaches the orchestrator, and how much of it
// the panel keeps in `details`. Chain mode is exempt from the cap: there the text
// is the handoff, so truncating it would break the flow instead of saving context.
const MAX_OUTPUT_BYTES = 16 * 1024;
const MAX_CALL_LINES = 4;
// The panel is bounded everywhere else, and the header line stays so.
const MAX_SKILLS = 8;

// Only `/antz` may dispatch, so the tool starts inactive and is turned on by
// that input. "The run is over" means `.antz/` is gone — which the orchestrator
// decides, once the decision document is written — and that keeps the tool alive
// through a clarify turn that ends to ask the user, through repairs, and through
// a run left half-done. When in doubt it stays active: a run that cannot
// dispatch is worse than a stale tool.
function setAntzToolActive(pi: ExtensionAPI, active: boolean): void {
  const current = pi.getActiveTools();
  if (active === current.includes(TOOL_NAME)) return;
  pi.setActiveTools(active ? [...current, TOOL_NAME] : current.filter((name) => name !== TOOL_NAME));
}

interface AgentDef {
  model?: string;
  tools?: string[];
  // Passed as the task, not as a system prompt, so the shared system prompt is
  // not split per agent.
  instructions: string;
}

function findAgentFile(cwd: string, name: string): string {
  const project = join(cwd, CONFIG_DIR_NAME, "agents", `${name}.md`);
  const user = join(getAgentDir(), "agents", `${name}.md`);
  if (existsSync(project)) return project;
  if (existsSync(user)) return user;
  throw new Error(`not found in ${project} or ${user}`);
}

// `tools:` is a comma list or a YAML array; anything else means "all default".
function parseToolList(value: unknown): string[] | undefined {
  const raw = Array.isArray(value) ? value : typeof value === "string" ? value.split(",") : [];
  const tools = raw
    .filter((tool): tool is string => typeof tool === "string")
    .map((tool) => tool.trim())
    .filter(Boolean);
  return tools.length > 0 ? tools : undefined;
}

function loadAgent(cwd: string, name: string): AgentDef {
  const raw = readFileSync(findAgentFile(cwd, name), "utf8");
  const { frontmatter, body } = parseFrontmatter<Record<string, unknown>>(raw);
  return {
    model: typeof frontmatter.model === "string" ? frontmatter.model : undefined,
    tools: parseToolList(frontmatter.tools),
    instructions: body.trim(),
  };
}

// One runtime for the process: it already knows the stored credentials and
// custom models, so parallel children don't each re-read the catalogs.
let runtime: Promise<ModelRuntime> | undefined;
function modelRuntime(): Promise<ModelRuntime> {
  return (runtime ??= ModelRuntime.create());
}

type RunStatus = "queued" | "running" | "done" | "failed";

interface ToolStep {
  tool: string;
  arg: string;
  // undefined while it runs, then whether it failed.
  failed?: boolean;
}

// pi's own usage type, so the tool result carries the nested LLM spend in the
// shape pi already sums (footer, `/session`, RPC) instead of a local mirror.
type RunUsage = NonNullable<AgentToolResult["usage"]>;

interface AgentRun {
  agent: string;
  task: string;
  status: RunStatus;
  // Which chain this run belongs to and which step of it, when the call was
  // `chains`. Unset for the other three shapes, whose runs are a flat list.
  group?: number;
  step?: number;
  // This, not the child's prose, is what answers "what is it doing".
  steps: ToolStep[];
  // The last thing the child said, not all of it: the only prose worth reading
  // when something looks wrong. Capped like `content`, so details stay bounded.
  lastText?: string;
  // toolCallId -> the step its start pushed, so the end event can mark it. A
  // plain object, not a Map: details get serialized to the session file.
  open: Record<string, ToolStep>;
  // What it actually runs with — the agent file's pin, or the session's model and
  // thinking level when it declares none. Read back from the child's session, so
  // the panel proves the pin instead of repeating the frontmatter.
  engine?: string;
  // The skills this run actually put to work, in the order it read them. pi only
  // advertises a skill, so a `read` of its SKILL.md is the only proof it was used.
  skillsUsed?: string[];
  // Token accounting for this child, read from its session once the run ends so
  // the tool result can carry the nested usage pi totals.
  usage?: RunUsage;
  error?: string;
  startedAt?: number;
  endedAt?: number;
}

interface AntzDetails {
  mode: "single" | "tasks" | "chain" | "chains";
  runs: AgentRun[];
  // The skills every child was handed, by name. Stated once because all of them
  // share a cwd and agentDir — and in a foreign repo it is also the record of
  // what antz found there.
  skills?: string[];
}

// The child's events, as far as the panel cares about them.
interface ChildEvent {
  type?: string;
  toolCallId?: string;
  toolName?: string;
  args?: unknown;
  isError?: boolean;
  message?: unknown;
}

function newRun(agent: string, task: string): AgentRun {
  return { agent, task, status: "queued", steps: [], open: {} };
}

// The shape of a call, taking the first one it finds: it runs while rendering a
// half-streamed call, where exclusivity cannot be assumed yet, and in `execute`,
// which checks the shapes are exclusive before trusting the answer.
function modeOf(params: {
  agent?: unknown;
  task?: unknown;
  chain?: unknown[];
  chains?: unknown[][];
  tasks?: unknown[];
}): AntzDetails["mode"] {
  if (params.chains?.length) return "chains";
  return params.chain?.length ? "chain" : params.tasks?.length ? "tasks" : "single";
}

function oneLine(text: unknown, max: number): string {
  const line = String(text ?? "").split("\n", 1)[0].trim();
  return line.length > max ? `${line.slice(0, max - 1)}…` : line;
}

// The one argument worth a line in the panel: which file, which command.
function toolArg(args: unknown): string {
  if (!args || typeof args !== "object") return "";
  const record = args as Record<string, unknown>;
  for (const key of ["command", "path", "pattern", "query", "url"]) {
    if (typeof record[key] === "string") return oneLine(record[key], 64);
  }
  const first = Object.values(record).find((value) => typeof value === "string");
  return typeof first === "string" ? oneLine(first, 64) : "";
}

// Boundaries only — never `text_delta` — so a run costs a handful of repaints on
// top of the caller's one-second tick, instead of one per token.
function track(run: AgentRun, event: ChildEvent, skillOf?: (path: unknown) => string | undefined): boolean {
  switch (event.type) {
    case "tool_execution_start": {
      const step: ToolStep = { tool: String(event.toolName ?? "?"), arg: toolArg(event.args) };
      run.steps.push(step);
      run.open[String(event.toolCallId)] = step;
      // pi puts a skill's name and path in the child's system prompt and stops
      // there: the full instructions arrive only when the model reads the file.
      // That `read` is the signal, and the path is what names the skill — a skill
      // fetched another way (a `bash cat`, say) simply goes unnoticed.
      if (event.toolName === "read") {
        const skill = skillOf?.((event.args as Record<string, unknown> | undefined)?.path);
        if (skill && !run.skillsUsed?.includes(skill)) run.skillsUsed = [...(run.skillsUsed ?? []), skill];
      }
      return true;
    }
    case "tool_execution_end": {
      const step = run.open[String(event.toolCallId)];
      if (step) step.failed = Boolean(event.isError);
      delete run.open[String(event.toolCallId)];
      return step !== undefined;
    }
    case "message_end": {
      const text = messageText(event.message);
      if (!text || text === run.lastText) return false;
      run.lastText = capText(text, MAX_OUTPUT_BYTES);
      return true;
    }
    default:
      return false;
  }
}

function messageText(message: unknown): string {
  const { role, content } = message as { role?: string; content?: Array<{ type: string; text?: string }> };
  if (role !== "assistant" || !Array.isArray(content)) return "";
  return content
    .filter((part) => part.type === "text")
    .map((part) => part.text ?? "")
    .join("")
    .trim();
}

function lastAssistantText(session: { messages: readonly unknown[] }): string {
  for (const message of [...session.messages].reverse()) {
    const text = messageText(message);
    if (text) return text;
  }
  return "";
}

function formatMs(ms: number): string {
  if (ms < 60_000) return `${Math.round(ms / 1000)}s`;
  return `${Math.floor(ms / 60_000)}m${String(Math.round((ms % 60_000) / 1000)).padStart(2, "0")}s`;
}

function duration(run: AgentRun): string {
  if (run.startedAt === undefined) return "";
  return formatMs((run.endedAt ?? Date.now()) - run.startedAt);
}

// Wall clock of the whole call, not the sum of the children: the number a
// watcher checks.
function elapsed(runs: AgentRun[]): string {
  const starts = runs.map((run) => run.startedAt).filter((at): at is number => at !== undefined);
  if (starts.length === 0) return "";
  const ends = runs.map((run) => run.endedAt).filter((at): at is number => at !== undefined);
  // Every dispatched child sets endedAt in its finally, so a short count means at
  // least one is still going.
  const until = ends.length < starts.length ? Date.now() : Math.max(...ends);
  return formatMs(until - Math.min(...starts));
}

function lastAction(run: AgentRun): string {
  const step = run.steps[run.steps.length - 1];
  if (!step) return "thinking…";
  // The mark is also the phase: `…` means a tool is running right now, `✓` that
  // the child is back in the model writing its next move.
  const mark = step.failed === undefined ? " …" : step.failed ? " ✗" : " ✓";
  return `${step.tool} ${step.arg}`.trim() + mark;
}

// The partial `content`. Kept to a status line on purpose: if a partial ever did
// reach the model, it should be a status, not a fragment of a report.
function statusLine(details: AntzDetails): string {
  const count = (status: RunStatus) => details.runs.filter((run) => run.status === status).length;
  return `${TOOL_NAME} ${details.mode}: ${count("done")}/${details.runs.length} done, ${count("running")} running, ${count("failed")} failed`;
}

// Truncates on a byte boundary, so a multi-byte character is never cut in half.
function capText(text: string, limit: number): string {
  if (limit <= 0 || Buffer.byteLength(text, "utf8") <= limit) return text;
  let head = text.slice(0, limit);
  while (Buffer.byteLength(head, "utf8") > limit) head = head.slice(0, -1);
  return head;
}

// The orchestrator-facing version: says how many bytes the model is not seeing.
function capOutput(text: string, limit: number): string {
  const head = capText(text, limit);
  if (head === text) return text;
  const bytes = Buffer.byteLength(text, "utf8");
  return `${head}\n\n[truncated: ${bytes - Buffer.byteLength(head, "utf8")} of ${bytes} bytes omitted]`;
}

// The child session's own totals: input/output/cacheRead/cacheWrite come from
// its assistant messages, so retries and tool results are already counted. pi
// only reads the combined `cost.total` back, so the breakdown stays zero.
function sessionUsage(session: AgentSession): RunUsage {
  const { tokens, cost } = session.getSessionStats();
  return {
    input: tokens.input,
    output: tokens.output,
    cacheRead: tokens.cacheRead,
    cacheWrite: tokens.cacheWrite,
    totalTokens: tokens.total,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: cost },
  };
}

// Every child's usage, summed into the one number the tool result carries, so
// pi's session totals include the nested LLM calls.
function totalUsage(runs: AgentRun[]): RunUsage | undefined {
  const present = runs.flatMap((run) => (run.usage ? [run.usage] : []));
  if (present.length === 0) return undefined;
  return present.reduce((a, b) => ({
    input: a.input + b.input,
    output: a.output + b.output,
    cacheRead: a.cacheRead + b.cacheRead,
    cacheWrite: a.cacheWrite + b.cacheWrite,
    totalTokens: a.totalTokens + b.totalTokens,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: a.cost.total + b.cost.total },
  }));
}

async function runAgent(
  run: AgentRun,
  details: AntzDetails,
  ctx: ExtensionContext,
  signal: AbortSignal | undefined,
  onUpdate: (() => void) | undefined,
): Promise<string> {
  let session: Awaited<ReturnType<typeof createAgentSession>>["session"] | undefined;
  let unsubscribe: (() => void) | undefined;
  const abort = () => void session?.abort();
  try {
    // Dispatched is not the same as busy: "queued" is only honest until here, and
    // loading the agent and its resources is already work.
    run.status = "running";
    run.startedAt = Date.now();
    onUpdate?.();
    const agent = loadAgent(ctx.cwd, run.agent);
    const loader = new DefaultResourceLoader({
      cwd: ctx.cwd,
      agentDir: getAgentDir(),
      noExtensions: true,
    });
    await loader.reload();

    // Read from the loader the session is built with, not from a second scan that
    // could disagree with it. Named once for the whole call because every child
    // shares this cwd and agentDir.
    const { skills } = loader.getSkills();
    details.skills = skills.map((skill) => skill.name);
    const skillFiles = new Map(skills.map((skill) => [skill.filePath, skill.name]));
    // The model is told the absolute path, but a relative one has to resolve to
    // the same file: the child's cwd is the repo, not this process's.
    const skillOf = (path: unknown): string | undefined =>
      typeof path === "string" ? skillFiles.get(isAbsolute(path) ? path : join(ctx.cwd, path)) : undefined;

    const models = await modelRuntime();
    let model = ctx.model;
    let thinkingLevel = ctx.thinkingLevel;
    if (agent.model) {
      const pinned = resolveCliModel({ cliModel: agent.model, modelRuntime: models });
      if (pinned.error) throw new Error(pinned.error);
      if (pinned.model) model = pinned.model;
      if (pinned.thinkingLevel) thinkingLevel = pinned.thinkingLevel;
    }

    const created = await createAgentSession({
      cwd: ctx.cwd,
      agentDir: getAgentDir(),
      resourceLoader: loader,
      sessionManager: SessionManager.inMemory(ctx.cwd),
      modelRuntime: models,
      model,
      thinkingLevel,
      tools: agent.tools,
    });
    session = created.session;
    // Read back from the session instead of trusting what we passed: the level is
    // clamped to what the model supports, so this is the pair the child actually
    // runs with. Provider and id are spelled the way the frontmatter pin is, which
    // makes validating a comparison against the agent file, and the fallbacks keep
    // the panel populated if the state lags a step behind.
    const engineModel = session.agent.state.model ?? model;
    const engineThinking = session.agent.state.thinkingLevel ?? thinkingLevel;
    run.engine = engineModel
      ? [`${engineModel.provider}/${engineModel.id}`, engineThinking].filter(Boolean).join(" · ")
      : "";
    onUpdate?.();

    unsubscribe = session.subscribe((event) => {
      if (track(run, event as ChildEvent, skillOf)) onUpdate?.();
    });

    if (signal?.aborted) abort();
    else signal?.addEventListener("abort", abort, { once: true });

    await session.prompt(`${agent.instructions}\n\n---\n\n${run.task}`, { expandPromptTemplates: false });
    if (session.agent.state.errorMessage) throw new Error(session.agent.state.errorMessage);
    run.status = "done";
    return lastAssistantText(session) || "(no output)";
  } catch (error) {
    run.status = "failed";
    run.error = error instanceof Error ? error.message : String(error);
    throw new Error(`${TOOL_NAME} ${run.agent}: ${run.error}`);
  } finally {
    run.endedAt = Date.now();
    run.usage = session ? sessionUsage(session) : undefined;
    // A tool still open here died with the run and never gets its end event, so
    // the panel must not leave it spinning.
    for (const step of Object.values(run.open)) step.failed = true;
    run.open = {};
    onUpdate?.();
    unsubscribe?.();
    signal?.removeEventListener("abort", abort);
    session?.dispose();
  }
}

async function mapConcurrent<T, R>(items: T[], limit: number, run: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (next < items.length) {
        const index = next++;
        results[index] = await run(items[index]);
      }
    }),
  );
  return results;
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", () => setAntzToolActive(pi, false));
  pi.on("input", (event) => {
    if (/^\/antz(\s|$)/.test(event.text.trimStart())) setAntzToolActive(pi, true);
  });
  pi.on("agent_settled", (_event, ctx) => {
    if (!existsSync(join(ctx.cwd, ".antz"))) setAntzToolActive(pi, false);
  });

  pi.registerTool({
    name: TOOL_NAME,
    label: "Antz Subagent",
    description:
      "Delegate to one of antz's isolated agents, with its own context window. Provide exactly one of: " +
      "{agent, task} for single, {tasks: [...]} for parallel, " +
      "{chain: [...]} for sequential handoff ({previous} is substituted), " +
      "{chains: [[...], ...]} for one chain per task in parallel ({previous} inside each, max 4 at once).",
    parameters: Type.Object({
      agent: Type.Optional(Type.String()),
      task: Type.Optional(Type.String()),
      tasks: Type.Optional(Type.Array(Type.Object({ agent: Type.String(), task: Type.String() }))),
      chain: Type.Optional(Type.Array(Type.Object({ agent: Type.String(), task: Type.String() }))),
      chains: Type.Optional(
        Type.Array(Type.Array(Type.Object({ agent: Type.String(), task: Type.String() }))),
      ),
    }),
    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const chain = params.chain ?? [];
      const chains = params.chains ?? [];
      const tasks = params.tasks ?? [];
      // Four shapes and no precedence between them: a call that provides two by
      // accident would otherwise run a shape the orchestrator did not ask for.
      const shapes = [chains.length > 0, chain.length > 0, tasks.length > 0, Boolean(params.agent && params.task)];
      if (shapes.filter(Boolean).length !== 1) {
        throw new Error(`${TOOL_NAME}: provide exactly one of agent+task, tasks, chain, or chains`);
      }
      const details: AntzDetails = { mode: modeOf(params), runs: [] };
      const update = () => onUpdate?.({ content: [{ type: "text", text: statusLine(details) }], details });
      const limit = details.mode === "chain" ? 0 : MAX_OUTPUT_BYTES;

      // A child parked in one long LLM call or one long command emits nothing, so
      // without a tick the clock would freeze at the last boundary — exactly when
      // a watcher wants to know it is still alive. Only a UI can show a clock, so
      // in print and json runs the tick is pure waste.
      const heartbeat = ctx.hasUI
        ? setInterval(() => {
            if (details.runs.some((run) => run.status === "running")) update();
          }, 1000)
        : undefined;

      try {
        if (chains.length) {
          // One chain per task, every chain in flight up to the same cap `tasks`
          // uses: the parallelism is a step the orchestrator takes, not a hope
          // that it happens to emit sibling `chain` calls. Inside a chain the
          // steps are sequential and `{previous}` is the handoff, so only the
          // chain's final text is capped — that is what the orchestrator reads.
          const groups = chains.map((steps, group) =>
            steps.map((step, index) => ({ ...newRun(step.agent, step.task), group, step: index })),
          );
          details.runs.push(...groups.flat());
          update();
          const results = await mapConcurrent(groups, MAX_CONCURRENCY, async (runs) => {
            let previous = "";
            try {
              for (const run of runs) {
                run.task = run.task.replaceAll("{previous}", previous);
                previous = await runAgent(run, details, ctx, signal, update);
              }
              return { runs, output: previous };
            } catch (error) {
              const message = error instanceof Error ? error.message : String(error);
              // One chain failing must not swallow the others' results, and the
              // steps behind it never ran: say so instead of leaving them queued.
              for (const run of runs) {
                if (run.status === "queued") {
                  run.status = "failed";
                  run.error = `not run: ${message}`;
                }
              }
              update();
              return { runs, output: message };
            }
          });
          const text = results
            .map(({ runs, output }) => {
              const failed = runs.some((run) => run.status === "failed");
              const label = runs.map((run) => run.agent).join(" → ");
              return failed ? `[${label}] FAILED — ${output}` : capOutput(output, limit);
            })
            .join("\n\n---\n\n");
          return {
            content: [{ type: "text", text }],
            details,
            usage: totalUsage(details.runs),
            isError: results.some(({ runs }) => runs.some((run) => run.status === "failed")),
          };
        }

        if (chain.length) {
          const runs = chain.map((step) => newRun(step.agent, step.task));
          details.runs.push(...runs);
          update();
          let previous = "";
          for (const run of runs) {
            run.task = run.task.replaceAll("{previous}", previous);
            previous = await runAgent(run, details, ctx, signal, update);
          }
          return { content: [{ type: "text", text: previous }], details, usage: totalUsage(runs) };
        }

        if (tasks.length) {
          const runs = tasks.map((task) => newRun(task.agent, task.task));
          details.runs.push(...runs);
          update();
          const results = await mapConcurrent(runs, MAX_CONCURRENCY, async (run) => {
            try {
              return { run, output: await runAgent(run, details, ctx, signal, update) };
            } catch (error) {
              return { run, output: error instanceof Error ? error.message : String(error) };
            }
          });
          const text = results
            .map(({ run, output }) =>
              run.status === "failed" ? `[${run.agent}] FAILED — ${output}` : `[${run.agent}]\n${capOutput(output, limit)}`,
            )
            .join("\n\n---\n\n");
          return {
            content: [{ type: "text", text }],
            details,
            usage: totalUsage(runs),
            isError: results.some(({ run }) => run.status === "failed"),
          };
        }

        if (params.agent && params.task) {
          const run = newRun(params.agent, params.task);
          details.runs.push(run);
          update();
          const output = await runAgent(run, details, ctx, signal, update);
          return { content: [{ type: "text", text: capOutput(output, limit) }], details, usage: totalUsage(details.runs) };
        }

        // Unreachable: the shape check admits exactly one of the four branches.
        throw new Error(`${TOOL_NAME}: provide exactly one of agent+task, tasks, chain, or chains`);
      } finally {
        if (heartbeat) clearInterval(heartbeat);
      }
    },

    renderCall(args, theme, context) {
      // A half-streamed `chains` can hold something that is not an array yet, and
      // rendering must not throw.
      const lines = (args.chains ?? []).map((steps) => (Array.isArray(steps) ? steps : []));
      const raw = args.chains?.length
        ? lines.map((steps) => ({
            agent: steps.map((step) => step.agent).join(" → "),
            task: steps.map((step) => step.task).join(" "),
          }))
        : args.chain?.length
          ? args.chain
          : args.tasks?.length
            ? args.tasks
            : args.agent
              ? [args]
              : [];
      // `{previous}` is only substituted once its step runs, so on the call it is
      // noise. The panel numbers its agents in this same order.
      const calls = raw.map((call) => ({
        agent: String(call.agent ?? "?"),
        task: String(call.task ?? "")
          .replaceAll("{previous}", "")
          .replace(/\s+/g, " ")
          .trim(),
      }));
      const numbered = calls.length > 1;
      const text = (context.lastComponent as Text | undefined) ?? new Text("", 0, 0);
      let content = theme.fg("toolTitle", theme.bold(`${TOOL_NAME} `));
      content += theme.fg("accent", modeOf(args));
      if (!context.argsComplete) content += theme.fg("muted", " …");
      for (const [index, call] of calls.slice(0, MAX_CALL_LINES).entries()) {
        const label = numbered ? `${index + 1}. ${call.agent}` : call.agent;
        content += `\n  ${theme.fg("accent", label)} ${theme.fg("dim", oneLine(call.task, 56))}`;
      }
      if (calls.length > MAX_CALL_LINES) {
        content += `\n  ${theme.fg("muted", `+${calls.length - MAX_CALL_LINES} more`)}`;
      }
      text.setText(content);
      return text;
    },

    renderResult(result, { expanded }, theme, context) {
      // The same component across repaints, which matters now that the panel is
      // repainted once a second.
      const text = (context.lastComponent as Text | undefined) ?? new Text("", 0, 0);
      const details = result.details as AntzDetails | undefined;
      if (!details?.runs.length) {
        const first = result.content[0];
        text.setText(first?.type === "text" ? first.text : "(no output)");
        return text;
      }

      const icon: Record<RunStatus, string> = {
        queued: theme.fg("muted", "○"),
        running: theme.fg("accent", "●"),
        done: theme.fg("success", "✓"),
        failed: theme.fg("error", "✗"),
      };
      const count = (status: RunStatus) => details.runs.filter((run) => run.status === status).length;
      // Four testers in parallel are four identical names, so number them: the
      // call's own list above uses the same order.
      const numbered = details.runs.length > 1;
      const label = (index: number, run: AgentRun) =>
        !numbered
          ? run.agent
          : run.group === undefined
            ? `${index + 1}. ${run.agent}`
            : `${run.group + 1}.${(run.step ?? 0) + 1} ${run.agent}`;
      const nameWidth = Math.max(...details.runs.map((run, index) => label(index, run).length));

      let header = theme.fg("toolTitle", theme.bold(`${TOOL_NAME} `));
      header += theme.fg("accent", details.mode);
      header += theme.fg("muted", ` (${details.runs.length})`);
      const clock = elapsed(details.runs);
      if (clock) header += theme.fg("muted", ` · ${clock}`);
      header += theme.fg("muted", ` · ${count("done")}/${details.runs.length} done`);
      if (count("running")) header += theme.fg("muted", ` · ${count("running")} running`);
      if (count("failed")) header += theme.fg("error", ` · ${count("failed")} failed`);

      const lines = [header];
      if (details.skills?.length) {
        const shown = details.skills.slice(0, MAX_SKILLS);
        const rest = details.skills.length - shown.length;
        lines.push(`  ${theme.fg("muted", `skills: ${shown.join(", ")}${rest > 0 ? ` +${rest} more` : ""}`)}`);
      }
      for (const [index, run] of details.runs.entries()) {
        if (!expanded) {
          const detail =
            run.status === "running"
              ? `${lastAction(run)} · ${duration(run)}`
              : run.status === "done"
                ? `done (${duration(run)})`
                : run.status === "failed"
                  ? oneLine(run.error ?? "failed", 48)
                  : "queued";
          const name = theme.fg(run.status === "failed" ? "error" : "text", label(index, run).padEnd(nameWidth));
          const engine = run.engine ? theme.fg("dim", `${run.engine} · `) : "";
          lines.push(`  ${icon[run.status]} ${name} ${engine}${theme.fg("muted", detail)}`);
          continue;
        }

        const spent = run.startedAt === undefined ? "" : theme.fg("dim", `  ${duration(run)}`);
        const engine = run.engine ? theme.fg("dim", ` · ${run.engine}`) : "";
        lines.push(
          "",
          `  ${icon[run.status]} ${theme.fg("toolTitle", theme.bold(label(index, run)))}${engine}${spent}`,
        );
        lines.push(`     ${theme.fg("dim", oneLine(run.task, 80))}`);
        for (const step of run.steps) {
          const mark =
            step.failed === undefined
              ? theme.fg("muted", " …")
              : step.failed
                ? theme.fg("error", " ✗")
                : theme.fg("success", " ✓");
          lines.push(`     ${theme.fg("muted", "→")} ${theme.fg("text", step.tool)} ${theme.fg("dim", step.arg)}${mark}`);
        }
        if (run.skillsUsed?.length) {
          lines.push(`     ${theme.fg("muted", `skills used: ${run.skillsUsed.join(", ")}`)}`);
        }
        if (run.lastText) {
          lines.push("");
          for (const line of run.lastText.split("\n")) lines.push(`     ${theme.fg("toolOutput", line)}`);
        }
        if (run.error) lines.push(`     ${theme.fg("error", oneLine(run.error, 80))}`);
      }
      lines.push(theme.fg("muted", `  ${keyHint("app.tools.expand", expanded ? "to collapse" : "to expand")}`));
      text.setText(lines.join("\n"));
      return text;
    },
  });
}
