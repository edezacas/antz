// ~/.pi/agent/extensions/antz-subagent.ts
//
// antz's subagent tool, with no third-party dependencies: every agent runs as
// its own AgentSession in this process (pi's own SDK — createAgentSession with
// a DefaultResourceLoader), never as a child `pi` process. There is no CLI flag
// to keep in sync with `pi --help`, and the agent's `tools:` allowlist and
// `model:` pin are enforced by the SDK rather than by arguments we hope it
// still accepts.
//
// Each child gets the agent's own system prompt, the repo's skills and
// AGENTS.md, and its declared tools — but no extensions: no recursion into
// this tool, no side effects from whatever else the session loaded.
//
// The tool is registered but starts inactive: antz is its only caller, so it
// stays out of every other session. `/antz` turns it on and it goes away when
// the run is over.

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  CONFIG_DIR_NAME,
  createAgentSession,
  DefaultResourceLoader,
  getAgentDir,
  ModelRuntime,
  parseFrontmatter,
  resolveCliModel,
  SessionManager,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const MAX_CONCURRENCY = 4;
const TOOL_NAME = "antz_subagent";

// Only `/antz` may dispatch, so the tool starts inactive and is turned on by
// that input. "The run is over" means `.antz/` is gone — the verifier deletes it
// on PASS — which keeps the tool alive through a clarify turn that ends the
// turn to ask the user, through repairs, and through a run left half-done. When
// in doubt it stays active: a run that cannot dispatch is worse than a stale
// tool.
function setAntzToolActive(pi: ExtensionAPI, active: boolean): void {
  const current = pi.getActiveTools();
  if (active === current.includes(TOOL_NAME)) return;
  pi.setActiveTools(active ? [...current, TOOL_NAME] : current.filter((name) => name !== TOOL_NAME));
}

interface AgentDef {
  model?: string;
  tools?: string[];
  systemPrompt: string;
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
    systemPrompt: body.trim(),
  };
}

// One runtime for the process: it already knows the stored credentials and
// custom models, so parallel children don't each re-read the catalogs.
let runtime: Promise<ModelRuntime> | undefined;
function modelRuntime(): Promise<ModelRuntime> {
  return (runtime ??= ModelRuntime.create());
}

function lastAssistantText(session: { messages: readonly unknown[] }): string {
  for (const message of [...session.messages].reverse()) {
    const { role, content } = message as { role?: string; content?: Array<{ type: string; text?: string }> };
    if (role !== "assistant" || !Array.isArray(content)) continue;
    const text = content
      .filter((part) => part.type === "text")
      .map((part) => part.text ?? "")
      .join("")
      .trim();
    if (text) return text;
  }
  return "";
}

async function runAgent(
  name: string,
  task: string,
  ctx: ExtensionContext,
  signal: AbortSignal | undefined,
): Promise<string> {
  let session: Awaited<ReturnType<typeof createAgentSession>>["session"] | undefined;
  const abort = () => void session?.abort();
  try {
    const agent = loadAgent(ctx.cwd, name);
    const loader = new DefaultResourceLoader({
      cwd: ctx.cwd,
      agentDir: getAgentDir(),
      appendSystemPrompt: [agent.systemPrompt],
      noExtensions: true,
    });
    await loader.reload();

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

    if (signal?.aborted) abort();
    else signal?.addEventListener("abort", abort, { once: true });

    await session.prompt(task, { expandPromptTemplates: false });
    if (session.agent.state.errorMessage) throw new Error(session.agent.state.errorMessage);
    return lastAssistantText(session) || "(no output)";
  } catch (error) {
    throw new Error(`${TOOL_NAME} ${name}: ${error instanceof Error ? error.message : String(error)}`);
  } finally {
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
      "{chain: [...]} for sequential handoff ({previous} is substituted).",
    parameters: Type.Object({
      agent: Type.Optional(Type.String()),
      task: Type.Optional(Type.String()),
      tasks: Type.Optional(Type.Array(Type.Object({ agent: Type.String(), task: Type.String() }))),
      chain: Type.Optional(Type.Array(Type.Object({ agent: Type.String(), task: Type.String() }))),
    }),
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      if (params.chain?.length) {
        let previous = "";
        for (const step of params.chain) {
          previous = await runAgent(step.agent, step.task.replaceAll("{previous}", previous), ctx, signal);
        }
        return { content: [{ type: "text", text: previous }] };
      }

      if (params.tasks?.length) {
        const results = await mapConcurrent(
          params.tasks,
          MAX_CONCURRENCY,
          async (task): Promise<{ agent: string; output: string; failed?: string }> => {
            try {
              return { agent: task.agent, output: await runAgent(task.agent, task.task, ctx, signal) };
            } catch (error) {
              return { agent: task.agent, output: "", failed: error instanceof Error ? error.message : String(error) };
            }
          },
        );
        const text = results
          .map((result) =>
            result.failed ? `[${result.agent}] FAILED — ${result.failed}` : `[${result.agent}]\n${result.output}`,
          )
          .join("\n\n---\n\n");
        return { content: [{ type: "text", text }], isError: results.some((result) => result.failed !== undefined) };
      }

      if (params.agent && params.task) {
        return { content: [{ type: "text", text: await runAgent(params.agent, params.task, ctx, signal) }] };
      }

      throw new Error(`${TOOL_NAME}: provide agent+task, tasks, or chain`);
    },
  });
}
