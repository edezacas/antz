// ~/.pi/agent/extensions/subagent.ts
//
// Minimal, dependency-free subagent tool: reads .md agent files (frontmatter
// parsed by hand, no yaml package), spawns each as an isolated `pi` process
// via pi.exec, and supports single / parallel / chain — no external package.
//
// Verify against your installed `pi --help` before relying on this:
// the exact one-shot flag names (-p, --no-session, model override) can
// differ between pi versions/forks. Adjust the buildArgs() function below
// if yours differ.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";

interface AgentDef {
  name: string;
  model?: string;
  tools?: string;
  systemPrompt: string;
}

function findAgentFile(name: string, cwd: string): string {
  const project = join(cwd, ".pi", "agents", `${name}.md`);
  const user = join(homedir(), ".pi", "agent", "agents", `${name}.md`);
  if (existsSync(project)) return project;
  if (existsSync(user)) return user;
  throw new Error(`Agent "${name}" not found in project or user agents/`);
}

function parseAgent(path: string): AgentDef {
  const raw = readFileSync(path, "utf8");
  const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) throw new Error(`No frontmatter in ${path}`);
  const [, front, body] = match;
  const fields: Record<string, string> = {};
  for (const line of front.split("\n")) {
    const m = line.match(/^(\w+):\s*(.*)$/);
    if (m) fields[m[1]] = m[2].trim();
  }
  return { name: fields.name, model: fields.model, tools: fields.tools, systemPrompt: body.trim() };
}

function buildArgs(agent: AgentDef, task: string): string[] {
  const prompt = `${agent.systemPrompt}\n\n---\nTask:\n${task}`;
  const args = ["-p", prompt, "--no-session"];
  if (agent.model) args.push("-m", agent.model);
  return args;
}

async function runAgent(
  pi: ExtensionAPI,
  agentName: string,
  task: string,
  cwd: string,
  signal: AbortSignal,
): Promise<string> {
  const agent = parseAgent(findAgentFile(agentName, cwd));
  const result = await pi.exec("pi", buildArgs(agent, task), { signal, timeout: 600_000, cwd });
  if (result.code !== 0) throw new Error(`${agentName} exited ${result.code}: ${result.stdout}`);
  return result.stdout.trim();
}

async function runParallel(
  pi: ExtensionAPI,
  tasks: { agent: string; task: string }[],
  cwd: string,
  signal: AbortSignal,
  concurrency = 4,
): Promise<string[]> {
  const results: string[] = new Array(tasks.length);
  let next = 0;
  async function worker() {
    while (next < tasks.length) {
      const i = next++;
      results[i] = await runAgent(pi, tasks[i].agent, tasks[i].task, cwd, signal);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, tasks.length) }, worker));
  return results;
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "subagent",
    label: "Subagent",
    description:
      "Delegate to an isolated agent process. Provide exactly one of: " +
      "{agent, task} for single, {tasks: [...]} for parallel, " +
      "{chain: [...]} for sequential handoff ({previous} is substituted).",
    parameters: Type.Object({
      agent: Type.Optional(Type.String()),
      task: Type.Optional(Type.String()),
      tasks: Type.Optional(Type.Array(Type.Object({ agent: Type.String(), task: Type.String() }))),
      chain: Type.Optional(Type.Array(Type.Object({ agent: Type.String(), task: Type.String() }))),
    }),
    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const cwd = ctx.cwd;

      if (params.chain) {
        let previous = "";
        const steps: string[] = [];
        for (const step of params.chain) {
          const task = step.task.replace("{previous}", previous);
          previous = await runAgent(pi, step.agent, task, cwd, signal);
          steps.push(previous);
        }
        return { content: [{ type: "text", text: previous }], details: { steps } };
      }

      if (params.tasks) {
        const results = await runParallel(pi, params.tasks, cwd, signal);
        return { content: [{ type: "text", text: results.join("\n\n---\n\n") }], details: { results } };
      }

      if (params.agent && params.task) {
        const text = await runAgent(pi, params.agent, params.task, cwd, signal);
        return { content: [{ type: "text", text }] };
      }

      throw new Error("subagent: provide agent+task, tasks, or chain");
    },
  });
}
