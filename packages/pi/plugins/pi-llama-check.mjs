// Test the patched extension with Pi's dependencies. Fake the server and
// session, so the tests need no model server or credentials.
import assert from "node:assert/strict";
import { createRequire, registerHooks } from "node:module";
import { join } from "node:path";
import { setImmediate as nextTurn } from "node:timers/promises";
import { pathToFileURL } from "node:url";
import { test } from "node:test";

const [extensionPath, piRoot] = process.argv.slice(2);
const requirePi = createRequire(join(piRoot, "package.json"));
const dependencyUrls = new Map(
  ["typebox", "typebox/compile", "@earendil-works/pi-tui"].map(
    (name) => [name, pathToFileURL(requirePi.resolve(name)).href],
  ),
);
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (dependencyUrls.has(specifier)) {
      return nextResolve(dependencyUrls.get(specifier), context);
    }
    return nextResolve(specifier, context);
  },
});
const aiRoot = join(piRoot, "node_modules/@earendil-works/pi-ai/dist");
const { getSupportedThinkingLevels } = await import(pathToFileURL(join(aiRoot, "models.js")));
const { streamSimple } = await import(pathToFileURL(join(aiRoot, "api/openai-completions.js")));
const { default: extension } = await import(pathToFileURL(extensionPath));

const qwenTemplate = `
{% if enable_thinking is undefined or enable_thinking is true %}
{% set resolved_reasoning_effort = reasoning_effort|default('xhigh') %}
{% if resolved_reasoning_effort not in ('xhigh', 'medium', 'low') %}
{{ raise_exception('Unsupported effort') }}
{% endif %}
{% endif %}`;
const props = (template = qwenTemplate, nCtx = 131072) => ({
  chat_template: template,
  default_generation_settings: { n_ctx: nCtx },
});
const catalog = () => Response.json({ data: [{
  id: "local-alias", status: { value: "loaded" }, meta: { n_ctx: 65536 },
}] });
const deferred = () => {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
};

async function setup(t, options = {}) {
  const events = new Map();
  const calls = [];
  const warnings = [];
  const widgets = [];
  const thinkingChanges = [];
  let provider;
  let active = { id: "hosted-test", provider: "hosted", reasoning: true };
  let thinking = "off";
  let stale = false;
  const ctx = {
    get model() {
      if (stale) throw new Error("context stale after session replacement");
      return active;
    },
    ui: {
      setWidget: (_key, widget) => widgets.push(widget),
      notify: (...args) => warnings.push(args),
      theme: { fg: (_color, text) => text },
    },
  };
  const pi = {
    registerCommand() {},
    registerProvider: (id, config) => { provider = { id, ...config }; },
    on: (name, handler) => events.set(name, handler),
    getThinkingLevel: () => thinking,
    setThinkingLevel: (level) => { thinking = level; thinkingChanges.push(level); },
  };
  t.mock.method(console, "warn", (...args) => warnings.push(args));
  t.mock.method(globalThis, "fetch", async (url, init = {}) => {
    const parsed = new URL(url);
    calls.push({ url: parsed, signal: init.signal });
    if (parsed.pathname.endsWith("/models/sse")) return new Response(null, { status: 404 });
    if (parsed.pathname.endsWith("/models")) return (options.models ?? catalog)(init.signal);
    if (parsed.pathname === "/props") {
      return options.metadata ? options.metadata(init.signal) : Response.json(props());
    }
    throw new Error(`Unexpected request: ${url}`);
  });
  await extension(pi);
  const emit = async (name, event = {}) => events.get(name)?.(event, ctx);
  t.after(async () => { await emit("session_shutdown"); });
  return {
    emit, calls, warnings, widgets, thinkingChanges,
    get provider() { return provider; },
    get active() { return active; },
    get thinking() { return thinking; },
    setStale: () => { stale = true; },
    useLocal() {
      active = { ...provider.models[0], provider: provider.id, api: provider.api, baseUrl: provider.baseUrl };
      return active;
    },
    useHosted() { active = { id: "hosted-test", provider: "hosted", reasoning: true }; },
  };
}

test("hosted startup and model picker tolerate an unavailable server silently", async (t) => {
  const h = await setup(t, { models: () => { throw new Error("connection refused"); } });
  await h.emit("session_start");
  await h.emit("before_agent_start");
  assert.equal(h.calls.length, 1);
  await h.emit("input", { text: "/model" });
  assert.equal(h.calls.length, 2);
  assert.deepEqual(h.warnings, []);
  assert.deepEqual(h.thinkingChanges, []);
});

test("automatic catalog requests time out within one second", async (t) => {
  // AbortSignal.timeout is unref'ed; keep the process alive for the mock I/O.
  const keepAlive = setInterval(() => {}, 100);
  t.after(() => clearInterval(keepAlive));
  let signal;
  const start = performance.now();
  const h = await setup(t, { models: (value) => {
    signal = value;
    assert.ok(signal instanceof AbortSignal);
    return new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(signal.reason), { once: true });
    });
  } });
  assert.equal(signal.aborted, true);
  assert.ok(performance.now() - start < 2000, "allow one second of scheduling slack");
  assert.deepEqual(h.warnings, []);
});

test("HTTP and malformed catalog failures stay quiet during hosted use", async (t) => {
  for (const models of [
    () => new Response(null, { status: 503 }),
    () => new Response("not JSON"),
    () => Response.json({ data: "invalid" }),
    () => Response.json({ data: [] }),
  ]) {
    await t.test(String(models), async (t) => {
      const h = await setup(t, { models });
      await h.emit("input", { text: "/model" });
      assert.deepEqual(h.warnings, []);
    });
  }
});

test("local startup awaits metadata and retains the full context token limit", async (t) => {
  const body = deferred();
  const h = await setup(t, { metadata: () => ({ ok: true, json: () => body.promise }) });
  h.useLocal();
  assert.equal(h.active.maxTokens, 65536);
  let started = false;
  const startup = h.emit("session_start").then(() => { started = true; });
  await nextTurn();
  assert.equal(started, false);
  body.resolve(props());
  await startup;
  assert.equal(h.active.contextWindow, 131072);
  assert.equal(h.active.maxTokens, 131072);
  assert.equal(h.thinking, "medium");
  assert.deepEqual(getSupportedThinkingLevels(h.active), ["off", "low", "medium", "max"]);
});

test("late local metadata cannot change a hosted model or its thinking level", async (t) => {
  const body = deferred();
  let signal;
  const h = await setup(t, { metadata: (value) => {
    signal = value;
    return { ok: true, json: () => body.promise };
  } });
  h.useLocal();
  const startup = h.emit("session_start");
  await nextTurn();
  h.useHosted();
  await h.emit("model_select", { model: h.active });
  assert.equal(signal.aborted, true);
  const widgetCount = h.widgets.length;
  body.resolve(props()); // Simulate a body that finishes despite cancellation.
  await startup;
  assert.equal(h.active.provider, "hosted");
  assert.deepEqual(h.thinkingChanges, []);
  assert.equal(h.widgets.length, widgetCount);
  assert.deepEqual(h.warnings, []);
});

test("switching away and back rejects old results without cancelling the new request", async (t) => {
  const oldBody = deferred();
  const newBody = deferred();
  const signals = [];
  const h = await setup(t, { metadata: (signal) => {
    signals.push(signal);
    return { ok: true, json: () => signals.length === 1 ? oldBody.promise : newBody.promise };
  } });
  h.useLocal();
  const oldStartup = h.emit("session_start");
  await nextTurn();
  h.useHosted();
  await h.emit("model_select", { model: h.active });
  h.useLocal();
  await h.emit("model_select", { model: h.active });
  await nextTurn();
  assert.equal(signals.length, 2);
  oldBody.resolve(props(qwenTemplate, 8192));
  await oldStartup;
  assert.equal(signals[1].aborted, false);
  assert.deepEqual(h.thinkingChanges, []);
  newBody.resolve(props(qwenTemplate, 131072));
  await nextTurn();
  assert.equal(h.active.contextWindow, 131072);
  assert.deepEqual(h.thinkingChanges, ["medium"]);
});

test("session shutdown ignores delayed metadata even when the old context is stale", async (t) => {
  const body = deferred();
  const h = await setup(t, { metadata: () => ({ ok: true, json: () => body.promise }) });
  h.useLocal();
  const startup = h.emit("session_start");
  await nextTurn();
  await h.emit("session_shutdown");
  h.setStale();
  body.resolve(props());
  await startup;
  assert.deepEqual(h.thinkingChanges, []);
  assert.deepEqual(h.warnings, []);
});

test("non-Qwen templates keep upstream behavior without inheriting Qwen effort values", async (t) => {
  for (const [name, template, levels] of [
    ["boolean thinking", "{% if enable_thinking %}think{% endif %}", ["off", "medium"]],
    ["different effort contract", "{% if enable_thinking and reasoning_effort not in ['low', 'medium', 'high'] %}error{% endif %}", ["off", "medium"]],
    ["effort without a thinking toggle", "{{ reasoning_effort }}", ["off"]],
    ["ordinary instruct model", "{{ messages }}", ["off"]],
  ]) {
    await t.test(name, async (t) => {
      const h = await setup(t, { metadata: () => Response.json(props(template)) });
      h.useLocal();
      await h.emit("session_start");
      assert.deepEqual(getSupportedThinkingLevels(h.active), levels);
      assert.notEqual(h.active.compat?.thinkingFormat, "chat-template");
      assert.equal(h.active.thinkingLevelMap?.max, undefined);
    });
  }
});

test("recognized effort contracts produce valid low/medium/max and off payloads", async (t) => {
  for (const template of [
    qwenTemplate,
    '{% if enable_thinking and reasoning_effort not in ["low", "medium", "xhigh",] %}error{% endif %}',
  ]) {
    await t.test(template, async (t) => {
      const h = await setup(t, { metadata: () => Response.json(props(template)) });
      h.useLocal();
      await h.emit("session_start");
      for (const level of ["off", "low", "medium", "max"]) {
        let payload;
        await streamSimple(h.active, {
          messages: [{ role: "user", content: "test", timestamp: 0 }],
        }, {
          apiKey: "test-only",
          reasoning: level === "off" ? undefined : level,
          onPayload: (body) => { payload = body; throw new Error("Captured before network access"); },
          fetch: async () => { throw new Error("Unexpected provider request"); },
        }).result();
        assert.deepEqual(payload.chat_template_kwargs, {
          enable_thinking: level !== "off",
          preserve_thinking: true,
          ...(level === "off" ? {} : { reasoning_effort: level === "max" ? "xhigh" : level }),
        });
        assert.equal(payload.thinking_budget_tokens, undefined);
      }
    });
  }
});
