import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

const [extensionPath, piRoot, noDocsPath] = process.argv.slice(2);
const load = (path) => import(pathToFileURL(path));
const { default: extension } = await load(extensionPath);
const { default: noDocs } = await load(noDocsPath);
const { buildSystemPrompt } = await load(join(piRoot, "dist/core/system-prompt.js"));
const { streamSimple } = await load(join(piRoot,
  "node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js"));

function setup(options = { cwd: "/", contextFiles: [] }) {
  const handlers = new Map();
  const views = [];
  const notices = [];
  let command;
  const ctx = {
    getSystemPrompt: () => buildSystemPrompt(options),
    getSystemPromptOptions: () => options,
    ui: {
      editor: async (title, text) => { views.push({ title, text }); return "discard these edits"; },
      notify: (text) => notices.push(text),
    },
  };
  extension({
    on: (name, handler) => handlers.set(name, handler),
    registerCommand(name, definition) {
      assert.equal(name, "system-prompt");
      command = definition.handler;
    },
  });
  return {
    views, notices, ctx,
    emit: (name, event = {}) => handlers.get(name)?.(event, ctx),
    show: () => command("", ctx),
  };
}

test("startup and session changes show a fresh preview without docs", async () => {
  const h = setup();
  await h.show();
  assert.match(h.views.at(-1).title, /preview/);
  assert.ok(!h.views.at(-1).text.includes("<docs>"));
  const preview = h.views.at(-1).text;
  for (const reason of ["startup", "new", "resume", "fork", "reload"]) {
    h.emit("before_provider_request", { payload: { instructions: "Previous session" } });
    h.emit("session_start", { reason });
    await h.show();
    assert.match(h.views.at(-1).title, /preview/);
    assert.equal(h.views.at(-1).text, preview);
  }
  assert.deepEqual(h.notices, []);
});

test("the preview matches the OpenAI request and the snapshot stays available when idle", async () => {
  let strip;
  noDocs({ on: (_name, handler) => { strip = handler; } });
  const options = {
    cwd: "/project",
    selectedTools: ["read", "bash"],
    toolSnippets: { read: "Read a file", bash: "Run a command" },
    contextFiles: [{ path: "/project/AGENTS.md", content: "Keep project instructions." }],
    skills: [{ name: "example", description: "Example skill", filePath: "/skills/example/SKILL.md" }],
    appendSystemPrompt: "Keep this instruction.",
  };
  const h = setup(options);
  const originalOptions = structuredClone(options);
  await h.show();
  const preview = h.views.at(-1).text;
  assert.deepEqual(options, originalOptions);
  const base = buildSystemPrompt(options);
  const { systemPrompt } = strip({ systemPrompt: base, systemPromptOptions: options });
  const model = {
    id: "local-model", provider: "llama-cpp", api: "openai-completions",
    baseUrl: "http://localhost:8080/v1", reasoning: false, input: ["text"],
    contextWindow: 32768, maxTokens: 8192,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  };
  let request;
  const stream = streamSimple(model, { messages: [
    { role: "system", content: systemPrompt, timestamp: 0 },
    { role: "user", content: "Hi", timestamp: 0 },
  ] }, {
    apiKey: "local", maxRetries: 0,
    onPayload: (payload) => h.emit("before_provider_request", { payload }),
    fetch: async (_url, init) => {
      request = JSON.parse(init.body);
      const chunk = { choices: [{ index: 0, delta: { content: "Hello" }, finish_reason: "stop" }] };
      return new Response(`data: ${JSON.stringify(chunk)}\n\ndata: [DONE]\n\n`, {
        headers: { "content-type": "text/event-stream" },
      });
    },
  });
  const result = await stream.result();
  assert.equal(result.stopReason, "stop", result.errorMessage);
  assert.equal(preview, request.messages[0].content);
  for (const text of ["Read a file", "Run a command", "Keep project instructions.", "/skills/example/SKILL.md"]) {
    assert.ok(preview.includes(text), text);
  }
  h.emit("agent_end");
  h.ctx.getSystemPrompt = () => { throw new Error("Use the captured request after a turn"); };
  await h.show();
  assert.match(h.views.at(-1).title, /Last provider request/);
  assert.equal(h.views.at(-1).text, request.messages[0].content);
  assert.ok(!h.views.at(-1).text.includes("<docs>"));
  assert.ok(h.views.at(-1).text.includes("Keep this instruction."));
  await h.show();
  assert.equal(h.views.at(-1).text, request.messages[0].content);

  h.emit("before_provider_request", { payload: { messages: [{ role: "developer", content: "Next call" }] } });
  await h.show();
  assert.equal(h.views.at(-1).text, "Next call");
});

test("preview uses current options, preserves custom prompts, and reports format drift", async () => {
  const options = { cwd: "/", selectedTools: ["read"], toolSnippets: { read: "Read a file" } };
  const h = setup(options);
  await h.show();
  assert.ok(h.views.at(-1).text.includes("Read a file"));
  options.selectedTools = [];
  options.customPrompt = "Custom instructions";
  await h.show();
  let beforeAgentStart;
  noDocs({ on: (_name, handler) => { beforeAgentStart = handler; } });
  const base = buildSystemPrompt(options);
  const result = beforeAgentStart({ systemPrompt: base, systemPromptOptions: options });
  assert.equal(h.views.at(-1).text, result?.systemPrompt ?? base);
  assert.ok(h.views.at(-1).text.includes("Custom instructions"));
  assert.ok(!h.views.at(-1).text.includes("Read a file"));

  delete options.customPrompt;
  h.ctx.getSystemPrompt = () => "Unknown default prompt format";
  await assert.rejects(h.show(), /the default prompt has no docs block/);
});

test("provider system blocks retain their structure and exclude user messages", async () => {
  const h = setup();
  const blocks = [{ type: "text", text: "Provider identity" },
    { type: "text", text: "Instructions", cache_control: { type: "ephemeral" } }];
  const cases = [
    [{ system: blocks, messages: [{ role: "user", content: "private" }] }, { system: blocks }],
    [{ instructions: "Initial", input: [{ role: "developer", content: "Update" },
      { role: "user", content: "private" }] },
    { instructions: "Initial", input: [{ role: "developer", content: "Update" }] }],
  ];
  for (const [payload, expected] of cases) {
    h.emit("before_provider_request", { payload });
    await h.show();
    assert.deepEqual(JSON.parse(h.views.at(-1).text), expected);
  }
  for (const payload of [{ instructions: "" }, { config: { systemInstruction: "Google prompt" } }]) {
    h.emit("before_provider_request", { payload });
    await h.show();
    assert.equal(h.views.at(-1).text, payload.instructions ?? payload.config.systemInstruction);
  }
  const count = h.views.length;
  for (const payload of [null, {}, { messages: [{ role: "user", content: "Hi" }] }]) {
    h.emit("before_provider_request", { payload });
    await h.show();
    assert.match(h.notices.at(-1), /No system prompt field/);
    assert.equal(h.views.length, count);
  }
});
