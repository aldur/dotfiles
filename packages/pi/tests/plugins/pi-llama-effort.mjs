// Test the extension with models from Pi's built-in llama.cpp provider. Fake
// the server and session, so the tests need no model server or credentials.
import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

const [extensionPath, piRoot] = process.argv.slice(2);
const load = (path) => import(pathToFileURL(path));
const { default: extension } = await load(extensionPath);
const { createLlamaProvider } = await load(join(piRoot, "dist/extensions/llama/provider.js"));
const aiRoot = join(piRoot, "node_modules/@earendil-works/pi-ai/dist");
const { getSupportedThinkingLevels } = await load(join(aiRoot, "models.js"));
const { streamSimple } = await load(join(aiRoot, "api/openai-completions.js"));

const qwenTemplate = `
{% if enable_thinking is undefined or enable_thinking is true %}
{% set resolved_reasoning_effort = reasoning_effort|default('xhigh') %}
{% if resolved_reasoning_effort not in ('xhigh', 'medium', 'low') %}
{{ raise_exception('Unsupported effort') }}
{% endif %}
{% endif %}`;
const serverUrl = "http://llama.test:8080";

async function setup(t, { template = qwenTemplate } = {}) {
  const requests = [];
  let props = () => Response.json({ chat_template: template });
  t.mock.method(globalThis, "fetch", async (input, init) => {
    const url = new URL(input);
    requests.push({ path: url.pathname, model: url.searchParams.get("model"), headers: init?.headers });
    if (url.pathname === "/models") {
      return Response.json({ data: [{ id: "local", status: { value: "loaded" }, meta: { n_ctx: 65536 } }] });
    }
    if (url.pathname === "/props") return props();
    throw new Error(`Unexpected request: ${url}`);
  });
  const { provider } = createLlamaProvider();
  await provider.refreshModels({
    allowNetwork: true,
    signal: new AbortController().signal,
    credential: { type: "api_key", key: "secret", env: { LLAMA_BASE_URL: `${serverUrl}/v1` } },
    publish: async ({ update }) => { update(); return true; },
  });
  const [model] = provider.getModels();
  requests.length = 0;

  const handlers = new Map();
  const warnings = [];
  extension({ on: (name, handler) => handlers.set(name, handler) });
  const ctx = {
    model,
    modelRegistry: { getApiKeyAndHeaders: async () => ({ ok: true, apiKey: "secret", headers: {} }) },
    ui: { notify: (text, level) => warnings.push([text, level]) },
  };
  return {
    model, requests, warnings,
    failProps: () => { props = () => new Response("", { status: 500 }); },
    emit: (name, event = {}) => handlers.get(name)(event, ctx),
  };
}

async function capturePayload(model, level) {
  let payload;
  await streamSimple(model, { messages: [{ role: "user", content: "test", timestamp: 0 }] }, {
    apiKey: "test-only", reasoning: level === "off" ? undefined : level,
    onPayload: (body) => { payload = body; throw new Error("Captured before network access"); },
    fetch: async () => { throw new Error("Unexpected provider request"); },
  }).result();
  assert.ok(payload, "Pi generated a request");
  return payload;
}

test("the built-in provider offers only off and medium for a Qwen template", async (t) => {
  const h = await setup(t);
  assert.equal(h.model.reasoning, true);
  assert.deepEqual(getSupportedThinkingLevels(h.model), ["off", "medium"]);
});

test("a Qwen effort template gets graded levels on session start", async (t) => {
  const h = await setup(t);
  await h.emit("session_start");
  assert.deepEqual(h.requests, [{ path: "/props", model: "local", headers: { Authorization: "Bearer secret" } }]);
  assert.deepEqual(getSupportedThinkingLevels(h.model), ["off", "low", "medium", "max"]);
  for (const [level, effort] of [["low", "low"], ["medium", "medium"], ["max", "xhigh"]]) {
    const kwargs = (await capturePayload(h.model, level)).chat_template_kwargs;
    assert.deepEqual(kwargs, { enable_thinking: true, preserve_thinking: true, reasoning_effort: effort });
  }
  const off = (await capturePayload(h.model, "off")).chat_template_kwargs;
  assert.deepEqual(off, { enable_thinking: false, preserve_thinking: true });
  assert.deepEqual(h.warnings, []);
});

test("model selection upgrades the selected model once", async (t) => {
  const h = await setup(t);
  await h.emit("model_select", { model: h.model });
  await h.emit("model_select", { model: h.model });
  assert.equal(h.requests.length, 1);
  assert.deepEqual(getSupportedThinkingLevels(h.model), ["off", "low", "medium", "max"]);
});

test("other templates keep the built-in levels", async (t) => {
  const boolean = "{% if enable_thinking %}<think>{% endif %}";
  const other = boolean + "{% if reasoning_effort not in ('low', 'high') %}{% endif %}";
  for (const template of [boolean, other]) {
    await t.test(template, async (t) => {
      const h = await setup(t, { template });
      await h.emit("session_start");
      assert.deepEqual(getSupportedThinkingLevels(h.model), ["off", "medium"]);
      assert.equal(h.model.compat.thinkingFormat, "qwen-chat-template");
    });
  }
});

test("non-reasoning and other provider models get no request", async (t) => {
  const h = await setup(t);
  await h.emit("model_select", { model: { ...h.model, reasoning: false } });
  await h.emit("model_select", { model: { ...h.model, provider: "openai" } });
  await h.emit("model_select", { model: undefined });
  assert.deepEqual(h.requests, []);
});

test("a failed /props request warns and keeps the built-in levels", async (t) => {
  const h = await setup(t);
  h.failProps();
  await h.emit("session_start");
  assert.deepEqual(getSupportedThinkingLevels(h.model), ["off", "medium"]);
  assert.deepEqual(h.warnings, [["[llama.cpp] cannot read effort levels of local: HTTP 500", "warning"]]);
});
