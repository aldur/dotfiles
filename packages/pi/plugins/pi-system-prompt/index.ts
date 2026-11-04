import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { prepareSystemPrompt } from "../pi-no-docs/index.ts";

function systemFields(payload: unknown): Record<string, unknown> | undefined {
  if (!payload || typeof payload !== "object") return;
  const request = payload as Record<string, unknown>;
  const fields: Record<string, unknown> = {};
  for (const key of ["instructions", "system", "systemInstruction"]) {
    if (request[key] !== undefined) fields[key] = request[key];
  }
  const config = request.config as Record<string, unknown> | undefined;
  if (config?.systemInstruction !== undefined) fields.systemInstruction = config.systemInstruction;
  for (const key of ["messages", "input"]) {
    if (Array.isArray(request[key])) {
      const messages = request[key].filter((message) =>
        message?.role === "system" || message?.role === "developer");
      if (messages.length) fields[key] = messages;
    }
  }
  return Object.keys(fields).length ? fields : undefined;
}

function displayPrompt(fields: Record<string, unknown>): string {
  const values = Object.values(fields);
  if (values.length === 1) {
    const value = values[0];
    if (typeof value === "string") return value;
    if (Array.isArray(value) && value.length === 1 && typeof value[0]?.content === "string") {
      return value[0].content;
    }
  }
  // Keep block boundaries and provider metadata when the prompt has multiple parts.
  return JSON.stringify(fields, null, 2);
}

export default function (pi: ExtensionAPI) {
  let lastPrompt: string | undefined;
  let observedRequest = false;

  pi.on("session_start", () => {
    lastPrompt = undefined;
    observedRequest = false;
  });
  pi.on("before_provider_request", (event) => {
    observedRequest = true;
    const fields = systemFields(event.payload);
    lastPrompt = fields ? displayPrompt(fields) : undefined;
  });

  pi.registerCommand("system-prompt", {
    description: "Show the last request's system prompt, or preview it before the first request",
    handler: async (_args, ctx) => {
      if (!observedRequest) {
        const preview = prepareSystemPrompt(ctx.getSystemPrompt(), ctx.getSystemPromptOptions());
        await ctx.ui.editor("System prompt preview (view only)", preview);
        return;
      }
      if (lastPrompt === undefined) {
        ctx.ui.notify("No system prompt field was found in the last provider request.", "info");
        return;
      }
      await ctx.ui.editor("Last provider request: system prompt (view only)", lastPrompt);
    },
  });
}
