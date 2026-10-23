/*
Copyright (c) 2026, Hugo Osvaldo Barrera <hugo@whynothugo.nl>

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
*/
import type { AgentMessage, AgentToolResult, AgentToolUpdateCallback, ThinkingLevel } from "@earendil-works/pi-agent-core";
import type { ExtensionAPI, ExtensionContext, Theme, ToolDefinition, ToolRenderResultOptions } from "@earendil-works/pi-coding-agent";
import {
  createAgentSession,
  DefaultResourceLoader,
  getAgentDir,
  SessionManager,
} from "@earendil-works/pi-coding-agent";
import type { Component } from "@earendil-works/pi-tui";
import { Text } from "@earendil-works/pi-tui";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type, Static } from "typebox";

type ContextMode = "fresh" | "fork";

const ThinkingLevelSchema = StringEnum(
  // Pi does not export these values, so we just have to duplicate them.
  ["off", "minimal", "low", "medium", "high", "xhigh"],
  { description: "Thinking level for the subagent" },
);

const ContextSchema = StringEnum(
  ["fresh", "fork"],
  { description: "fresh = new context, fork = inherit session context (default: fresh)" },
);

const SubagentParams = Type.Object({
  task: Type.String({ description: "Task description for the subagent" }),
  prompt: Type.Optional(Type.String({ description: "Custom system prompt" })),
  model: Type.Optional(Type.String({ description: "Child model: provider/id[:level], or an unambiguous available bare id" })),
  thinking: Type.Optional(ThinkingLevelSchema),
  context: Type.Optional(ContextSchema),
  sessionId: Type.Optional(Type.String({ description: "Resume a previous subagent session by ID" })),
});

type SubagentParamsType = Static<typeof SubagentParams>;

interface SubagentDetails {
  model: { provider: string; id: string };
  context: ContextMode;
  sessionId?: string;
  tokens: number;
  status?: "question" | "done";
}

function getExtensionPaths(pi: ExtensionAPI): string[] {
  const paths = new Set<string>();

  for (const tool of pi.getAllTools()) {
    const source = tool.sourceInfo.source;
    const path = tool.sourceInfo.path;
    // Skip builtin, sdk, and synthetic paths.
    if (source === "builtin" || source === "sdk" || path.startsWith("<")) continue;
    if (path) paths.add(path);
  }

  for (const cmd of pi.getCommands()) {
    if (cmd.source !== "extension") continue;
    const path = cmd.sourceInfo.path;
    // Skip synthetic paths.
    if (path.startsWith("<")) continue;
    if (path) paths.add(path);
  }

  return Array.from(paths);
}

// Returns a function which appends our custom system prompt to the base system prompt.
function buildSystemPromptOverride(customPrompt?: string): ((base: string | undefined) => string) | undefined {
  const instructions = "You are a subagent working for another agent, not a human. If you are blocked on information or a decision only the caller has, stop and end your reply with a final line starting with `QUESTION:` followed by the question. Otherwise finish the task and end with a concise report.";
  return (base: string | undefined) => [base, customPrompt, instructions].filter(Boolean).join("\n\n");
}

function getLastAssistantText(messages: AgentMessage[]): string | undefined {
  for (let i = messages.length - 1; i >= 0; i--) {
    const msg = messages[i];
    if (msg.role !== "assistant") continue;
    return msg.content.filter(part => part.type === "text").map(part => part.text).join("\n");
  }
  return undefined;
}

function getTotalTokens(messages: AgentMessage[]): number {
  let total = 0;
  for (const msg of messages) {
    if (msg.role === "assistant") {
      total += msg.usage?.totalTokens ?? 0;
    }
  }
  return total;
}

function formatTokens(count: number): string {
  if (count < 10000) return count.toString();
  if (count < 100000) return `${(count / 1000).toFixed(1)}k`;
  if (count < 10000000) return `${Math.round(count / 1000)}k`;
  return `${(count / 1000000).toFixed(1)}M`;
}

async function findSessionById(sessionId: string): Promise<string | undefined> {
  const sessions = await SessionManager.listAll();
  const session = sessions.find(s => s.id === sessionId);
  return session?.path;
}

function resolveModel(ctx: ExtensionContext, spec?: string, saved?: { provider: string; modelId: string }) {
  const available = ctx.modelRegistry.getAvailable();
  const fail = (reason: string): never => {
    const choices = available.slice(0, 10).map(m => `${m.provider}/${m.id}`).join(", ");
    throw new Error(`${reason}. Available models: ${choices || "(none)"}`);
  };
  let suffix: ThinkingLevel | undefined;
  let model: ExtensionContext["model"];
  if (spec !== undefined) {
    const match = spec.match(/:(off|minimal|low|medium|high|xhigh)$/);
    if (match) {
      suffix = match[1] as ThinkingLevel;
      spec = spec.slice(0, -match[0].length);
    }
    const slash = spec.indexOf("/");
    if (slash >= 0) {
      model = ctx.modelRegistry.find(spec.slice(0, slash), spec.slice(slash + 1));
    } else {
      const matches = available.filter(m => m.id === spec);
      if (matches.length > 1) fail(`Ambiguous model id: ${spec}; use provider/id`);
      model = matches[0];
    }
    if (!model) fail(`Unknown model: ${spec}`);
  } else if (saved) {
    model = ctx.modelRegistry.find(saved.provider, saved.modelId);
    if (!model) fail(`Unknown saved model: ${saved.provider}/${saved.modelId}`);
  } else {
    model = ctx.model;
    if (!model) fail("No parent model configured; pass model explicitly");
  }
  if (!available.some(m => m.provider === model!.provider && m.id === model!.id)) {
    fail(`Model has no available credentials: ${model!.provider}/${model!.id}`);
  }
  return { model: model!, suffix };
}

async function runSubagent(options: {
  cwd: string;
  task: string;
  customPrompt?: string;
  thinking: ThinkingLevel;
  context: ContextMode;
  sessionFile?: string;
  resumeManager?: SessionManager;
  signal?: AbortSignal;
  onUpdate?: AgentToolUpdateCallback<SubagentDetails>;
  model: ExtensionContext["model"];
  extensionPaths: string[];
  activeTools: string[];
}): Promise<{ output: string; sessionId: string; tokens: number; model: SubagentDetails["model"] }> {
  let sessionManager: SessionManager;

  options.signal?.throwIfAborted();
  if (options.resumeManager) {
    sessionManager = options.resumeManager;
  } else if (options.context === "fork" && options.sessionFile) {
    // Fork from the current parent session.
    const parentSm = SessionManager.open(options.sessionFile);
    const leafId = parentSm.getLeafId();
    if (!leafId) throw new Error("Parent session has no entries to fork");
    const newSessionPath = parentSm.createBranchedSession(leafId);
    if (!newSessionPath) throw new Error("Failed to create forked session");
    sessionManager = SessionManager.open(newSessionPath);
  } else {
    // Create a fresh session.
    sessionManager = SessionManager.create(options.cwd);
  }

  // No access to parent loader, create one with same paths.
  const loader = new DefaultResourceLoader({
    cwd: options.cwd,
    agentDir: getAgentDir(),
    additionalExtensionPaths: options.extensionPaths,
    systemPromptOverride: buildSystemPromptOverride(options.customPrompt),
  });
  await loader.reload();

  const sessionId = sessionManager.getSessionId();

  options.signal?.throwIfAborted();
  // The SDK creates its default modelRuntime; ctx exposes only the registry facade.
  const { session } = await createAgentSession({
    cwd: options.cwd,
    sessionManager,
    resourceLoader: loader,
    model: options.model,
    thinkingLevel: options.thinking,
  });

  // The SDK records initial selections for fresh sessions, but not explicit
  // overrides on existing/forked sessions. Persist those for later resumes.
  const entries = sessionManager.getEntries().reverse();
  const lastModel = entries.find(entry => entry.type === "model_change");
  const current = session.model;
  if (current && (lastModel?.type !== "model_change" || lastModel.provider !== current.provider || lastModel.modelId !== current.id)) {
    sessionManager.appendModelChange(current.provider, current.id);
  }
  const lastThinking = entries.find(entry => entry.type === "thinking_level_change");
  if (lastThinking?.type !== "thinking_level_change" || lastThinking.thinkingLevel !== session.thinkingLevel) {
    sessionManager.appendThinkingLevelChange(session.thinkingLevel);
  }

  // Name the session for easy identification.
  if (!options.resumeManager) {
    const name = options.task.length > 60
      ? `subagent: ${options.task.slice(0, 60)}...`
      : `subagent: ${options.task}`;
    session.setSessionName(name);
  }

  session.setActiveToolsByName(options.activeTools);

  const actualModel = () => {
    const model = session.model;
    if (!model) throw new Error("Subagent has no model");
    return { provider: model.provider, id: model.id };
  };
  options.onUpdate?.({ content: [], details: { model: actualModel(), context: options.context, sessionId, tokens: 0 } });

  const unsubscribe = session.subscribe((event) => {
    if (event.type === "message_end" && event.message.role === "assistant") {
      const tokens = getTotalTokens(session.agent.state.messages);
      options.onUpdate?.({
        content: [],
        details: {
          model: actualModel(),
          context: options.context,
          sessionId,
          tokens,
        },
      });
    }
  });

  const abortHandler = () => { void session.abort(); };
  options.signal?.addEventListener("abort", abortHandler);
  let tokens = 0;
  let output: string | undefined;
  let model: SubagentDetails["model"];
  try {
    options.signal?.throwIfAborted();
    await session.prompt(options.task);
    options.signal?.throwIfAborted();
    model = actualModel();
    tokens = getTotalTokens(session.agent.state.messages);
    output = getLastAssistantText(session.agent.state.messages);
  } finally {
    unsubscribe();
    options.signal?.removeEventListener("abort", abortHandler);
    session.dispose();
  }

  if (!output) {
    throw new Error("No response from subagent.");
  }
  return { output, sessionId, tokens, model };
}

export default function(pi: ExtensionAPI): void {
  const tool: ToolDefinition<typeof SubagentParams, SubagentDetails> = {
    name: "subagent",
    label: "Subagent",
    description: "Delegate a task to an isolated subagent.",
    promptSnippet: "Delegate to subagent with an isolated context.",
    promptGuidelines: [
      "Use subagents for multi-step work which would otherwise fill your context with raw output that you won't need again.",
      "Subagents can parallelise independent queries, assuming that any context generated by them won't be of importance.",
      "Use context=fork when the subagent needs the current context. Use context=fresh when providing extensive standalone instructions to the agent.",
      "Use the sessionId parameter to continue a previous subagent session. Continue a previous session when its context is valuable for a follow-up task.",
      "When a subagent returns a question, answer it by resuming that sessionId. Do not start a new subagent.",
      "Pass model to use a cheaper model for search or summarising, or a stronger one for hard reasoning. Omit it to inherit your own model.",
      "A resumed subagent keeps its original model unless model is passed.",
    ],
    parameters: SubagentParams,

    async execute(
      _toolCallId: string,
      params: SubagentParamsType,
      signal: AbortSignal | undefined,
      onUpdate: AgentToolUpdateCallback<SubagentDetails> | undefined,
      ctx: ExtensionContext,
    ): Promise<AgentToolResult<SubagentDetails>> {
      let resumeManager: SessionManager | undefined;
      if (params.sessionId) {
        const path = await findSessionById(params.sessionId);
        if (!path) throw new Error(`Session not found: ${params.sessionId}`);
        resumeManager = SessionManager.open(path);
      }
      const saved = resumeManager?.getEntries().reverse().find(entry => entry.type === "model_change");
      const { model, suffix } = resolveModel(ctx, params.model, saved?.type === "model_change" ? saved : undefined);
      const thinking: ThinkingLevel = (params.thinking as ThinkingLevel | undefined) ?? suffix ?? pi.getThinkingLevel();
      const context: ContextMode = (params.context as ContextMode | undefined) ?? "fresh";

      const sessionFile = ctx.sessionManager.getSessionFile();
      if (!resumeManager && context === "fork" && !sessionFile) {
        throw new Error("Cannot fork: no session file available.");
      }

      // Use extension paths and active tools from parent.
      const extensionPaths = getExtensionPaths(pi);
      const activeTools = pi.getActiveTools();

      const result = await runSubagent({
        cwd: ctx.cwd,
        task: params.task,
        customPrompt: params.prompt,
        thinking,
        context,
        sessionFile: sessionFile,
        resumeManager,
        signal,
        onUpdate,
        model,
        extensionPaths,
        activeTools,
      });

      // Include session ID in output so the agent can reference it for follow-ups.
      const question = result.output.split(/\r?\n/).find(line => line.startsWith("QUESTION:"));
      const status = question ? "question" : "done";
      const text = question
        ? `${question}\n\nThe subagent is waiting. Answer by calling subagent with sessionId "${result.sessionId}" and your answer as the task.`
        : result.output;
      const output = `${text}\n\n[Session ID: ${result.sessionId}]`;
      return {
        content: [{ type: "text", text: output }],
        details: { model: result.model, context, sessionId: result.sessionId, tokens: result.tokens, status }
      };
    },

    renderCall(args: SubagentParamsType, theme: Theme): Component {
      const mode = args.sessionId ? `resume ${args.sessionId}` : (args.context || "fresh");
      const task = theme.fg("dim", args.task);
      const title = `subagent (${mode}${args.model ? ` · ${args.model}` : ""})`;
      return new Text(`${theme.fg("toolTitle", theme.bold(title))}\n ${task}`, 0, 0);
    },

    renderResult(
      result: AgentToolResult<SubagentDetails>,
      options: ToolRenderResultOptions,
      theme: Theme,
    ): Component {
      const modelStr = result.details?.model
        ? ` via ${result.details.model.provider}/${result.details.model.id}`
        : "";
      const tokenStr = result.details?.tokens
        ? `, ${formatTokens(result.details.tokens)} tokens`
        : "";
      const state = options.isPartial ? "Running" : result.details?.status === "question" ? "Question" : "Completed";
      const header = theme.bold(`${state}${modelStr}${tokenStr}`);

      const content = result.content[0];
      const hasOutput = content?.type === "text" && content.text.length > 0;

      if (options.isPartial && !hasOutput) {
        return new Text(header, 0, 0);
      }

      const output = hasOutput ? content.text : "(no output)";
      return new Text(`${header}\n\n${output}`, 0, 0);
    },
  };

  pi.registerTool(tool);
}
