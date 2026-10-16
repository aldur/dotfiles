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
const { getSupportedThinkingLevels, clampThinkingLevel } = await import(pathToFileURL(join(aiRoot, "models.js")));
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
  let thinking = options.thinking ?? "off";
  let stale = false;
  const ctx = {
    sessionManager: { getBranch: () => options.entries ?? [] },
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
    useLocal(index = 0) {
      active = { ...provider.models[index], provider: provider.id, api: provider.api, baseUrl: provider.baseUrl };
      return active;
    },
    setThinking(level) { thinking = level; },
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

const advertisedCatalog = (efforts, defaultEffort = "off", fields = {}) => () => Response.json({ data: [{
  id: "local-alias", context_length: 128000,
  reasoning_efforts: efforts, default_reasoning_effort: defaultEffort, ...fields,
}] });

async function capturePayload(model, level, messages = [{ role: "user", content: "test", timestamp: 0 }]) {
  let payload;
  await streamSimple(model, { messages }, {
    apiKey: "test-only", reasoning: level === "off" ? undefined : level,
    onPayload: (body) => { payload = body; throw new Error("Captured before network access"); },
    fetch: async () => { throw new Error("Unexpected provider request"); },
  }).result();
  assert.ok(payload, "Pi generated a request");
  return payload;
}

test("advertised capabilities work without a template and respect an off default", async (t) => {
  const h = await setup(t, {
    models: advertisedCatalog(["off", "low", "medium", "xhigh"]),
    metadata: () => Response.json({ default_generation_settings: { n_ctx: 128000 } }),
  });
  h.useLocal();
  assert.equal(h.active.reasoning, true, "discover from the catalog before selection");
  await h.emit("session_start");
  assert.equal(h.thinking, "off");
  assert.deepEqual(h.thinkingChanges, []);
  assert.deepEqual(getSupportedThinkingLevels(h.active), ["off", "low", "medium", "xhigh"]);
  assert.equal(h.active.contextWindow, 128000);
  for (const level of getSupportedThinkingLevels(h.active)) {
    const payload = await capturePayload(h.active, level);
    assert.equal(payload.reasoning_effort, level);
    assert.equal(payload.chat_template_kwargs, undefined);
    assert.equal(payload.enable_thinking, undefined);
  }
});

test("only advertised values reach the wire for graded, binary and always-on models", async (t) => {
  for (const [efforts, defaultEffort, expectedLevels, defaultLevel] of [
    [["off", "low", "medium", "xhigh"], "medium", ["off", "low", "medium", "xhigh"], "medium"],
    [["none", "minimal", "low", "medium", "high"], "none", ["off", "minimal", "low", "medium", "high"], "off"],
    [["off", "on"], "on", ["off", "medium"], "medium"],
    [["low", "high", "max"], "high", ["low", "high", "max"], "high"],
    [["on"], "on", ["medium"], "medium"],
    [["medium"], "medium", ["medium"], "medium"],
  ]) {
    await t.test(efforts.join(","), async (t) => {
      const h = await setup(t, {
        models: advertisedCatalog(efforts, defaultEffort),
        metadata: () => Response.json(props()), // Catalog must outrank a conflicting template.
      });
      h.useLocal();
      await h.emit("session_start");
      assert.deepEqual(getSupportedThinkingLevels(h.active), expectedLevels);
      assert.equal(h.thinking, defaultLevel);
      for (const level of ["off", "minimal", "low", "medium", "high", "xhigh", "max"]) {
        const clamped = clampThinkingLevel(h.active, level);
        const payload = await capturePayload(h.active, clamped);
        assert.ok(efforts.includes(payload.reasoning_effort), `${level}: ${payload.reasoning_effort}`);
        assert.equal(payload.chat_template_kwargs, undefined);
      }
    });
  }
});

test("missing /props preserves catalog capabilities and avoids repeated probes", async (t) => {
  for (const status of [404, 405]) {
    await t.test(String(status), async (t) => {
      const h = await setup(t, {
        models: advertisedCatalog(["off", "low", "medium", "xhigh"]),
        metadata: () => new Response(null, { status }),
      });
      h.useLocal();
      await h.emit("session_start");
      h.setThinking("medium");
      await h.emit("before_agent_start");
      assert.equal(h.calls.filter(({ url }) => url.pathname === "/props").length, 1);
      await h.emit("input", { text: "/model" });
      h.useLocal();
      await h.emit("before_agent_start");
      assert.equal(h.thinking, "medium");
      assert.equal((await capturePayload(h.active, h.thinking)).reasoning_effort, "medium");
      assert.equal(h.calls.filter(({ url }) => url.pathname === "/props").length, 2, "manual refresh retries discovery");
      assert.deepEqual(h.warnings, []);
    });
  }
});

test("user choices survive catalog refresh, cached discovery and restored sessions", async (t) => {
  const h = await setup(t, {
    models: advertisedCatalog(["off", "low", "medium", "xhigh"], "medium", { status: { value: "loaded" } }),
    metadata: () => Response.json(props()),
  });
  h.useLocal();
  await h.emit("session_start");
  assert.equal(h.thinking, "medium");
  h.setThinking("off");
  await h.emit("before_agent_start");
  await h.emit("input", { text: "/model" });
  h.useLocal();
  await h.emit("before_agent_start");
  assert.equal(h.thinking, "off");
  for (const reason of ["resume", "fork", "reload"]) {
    await h.emit("session_start", { reason });
    assert.equal(h.thinking, "off");
  }
  assert.deepEqual(h.thinkingChanges, ["medium"]);
});

test("an existing supported Pi choice overrides the advertised default", async (t) => {
  const h = await setup(t, {
    thinking: "low", models: advertisedCatalog(["off", "low", "medium", "xhigh"]),
    metadata: () => Response.json({}),
  });
  h.useLocal();
  await h.emit("session_start");
  assert.equal(h.thinking, "low");
  assert.deepEqual(h.thinkingChanges, []);
});

test("startup of an existing conversation preserves its saved off choice", async (t) => {
  const h = await setup(t, {
    models: advertisedCatalog(["off", "on"], "on"),
    entries: [{ type: "message", message: { role: "user" } }],
    metadata: () => Response.json({}),
  });
  h.useLocal();
  await h.emit("session_start", { reason: "startup" });
  assert.equal(h.thinking, "off");
  assert.deepEqual(h.thinkingChanges, []);
});

test("mixed catalogs keep per-model capability and template contracts separate", async (t) => {
  const h = await setup(t, {
    models: () => Response.json({ data: [
      { id: "graded", reasoning_efforts: ["off", "low", "medium", "xhigh"], default_reasoning_effort: "off" },
      { id: "binary", reasoning_efforts: ["none", "on"], default_reasoning_effort: "none" },
      { id: "legacy", status: { value: "loaded" }, meta: { n_ctx: 65536 } },
    ] }),
  });
  for (const [index, levels, field, value] of [
    [0, ["off", "low", "medium", "xhigh"], "reasoning_effort", "medium"],
    [1, ["off", "medium"], "reasoning_effort", "on"],
    [2, ["off", "low", "medium", "max"], "chat_template_kwargs", { enable_thinking: true, preserve_thinking: true, reasoning_effort: "medium" }],
    [0, ["off", "low", "medium", "xhigh"], "reasoning_effort", "medium"],
  ]) {
    h.useLocal(index);
    await h.emit("model_select", { model: h.active });
    await nextTurn();
    assert.deepEqual(getSupportedThinkingLevels(h.active), levels);
    assert.deepEqual((await capturePayload(h.active, "medium"))[field], value);
  }
});

test("a refreshed model id can change its reasoning contract without stale request fields", async (t) => {
  let row = { reasoning_efforts: ["off", "low", "medium", "xhigh"], default_reasoning_effort: "off" };
  const h = await setup(t, {
    models: () => Response.json({ data: [{ id: "local-alias", status: { value: "loaded" }, ...row }] }),
  });
  h.useLocal();
  await h.emit("session_start");
  assert.equal((await capturePayload(h.active, "medium")).reasoning_effort, "medium");
  row = { reasoning_efforts: ["none", "on"], default_reasoning_effort: "none" };
  await h.emit("input", { text: "/model" });
  h.useLocal();
  await h.emit("before_agent_start");
  assert.equal((await capturePayload(h.active, "medium")).reasoning_effort, "on");
  row = {};
  await h.emit("input", { text: "/model" });
  h.useLocal();
  await h.emit("before_agent_start");
  const payload = await capturePayload(h.active, "medium");
  assert.equal(payload.reasoning_effort, undefined);
  assert.equal(payload.chat_template_kwargs.reasoning_effort, "medium");
});

test("reasoning deltas render as thinking and survive a tool-call round trip", async (t) => {
  const h = await setup(t, {
    models: advertisedCatalog(["off", "low", "medium", "xhigh"]),
    metadata: () => Response.json({}),
  });
  h.useLocal();
  await h.emit("session_start");
  const chunks = [
    { choices: [{ index: 0, delta: { role: "assistant", reasoning_content: "Check the ledger." }, finish_reason: null }] },
    { choices: [{ index: 0, delta: { tool_calls: [{ index: 0, id: "call_1", type: "function", function: { name: "read", arguments: '{"path":"ledger"}' } }] }, finish_reason: "tool_calls" }] },
  ];
  const events = [];
  const stream = streamSimple(h.active, { messages: [{ role: "user", content: "test", timestamp: 0 }] }, {
    apiKey: "test-only", reasoning: "medium",
    fetch: async () => new Response(
      chunks.map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`).join("") + "data: [DONE]\n\n",
      { headers: { "content-type": "text/event-stream" } },
    ),
  });
  for await (const event of stream) events.push(event.type);
  const reply = await stream.result();
  assert.ok(events.includes("thinking_delta"));
  assert.equal(reply.stopReason, "toolUse");
  assert.equal(reply.content[0].thinking, "Check the ledger.");
  const payload = await capturePayload(h.active, "medium", [
    { role: "user", content: "test", timestamp: 0 }, reply,
    { role: "toolResult", toolCallId: "call_1", toolName: "read", content: [{ type: "text", text: "ledger contents" }], isError: false, timestamp: 0 },
  ]);
  const assistant = payload.messages.find((message) => message.role === "assistant");
  assert.equal(assistant.reasoning_content, "Check the ledger.");
  assert.equal(assistant.tool_calls[0].id, "call_1");
});

test("malformed capability extensions do not discard models or template fallback", async (t) => {
  for (const efforts of [undefined, null, "low", [42], {}, ["future-effort"]]) {
    await t.test(JSON.stringify(efforts) ?? "absent", async (t) => {
      const h = await setup(t, { models: advertisedCatalog(efforts) });
      assert.equal(h.provider.models.length, 1);
      h.useLocal();
      await h.emit("session_start");
      assert.deepEqual(getSupportedThinkingLevels(h.active), ["off", "low", "medium", "max"]);
      assert.equal((await capturePayload(h.active, "max")).chat_template_kwargs.reasoning_effort, "xhigh");
      assert.deepEqual(h.warnings, []);
    });
  }
});

test("explicit non-reasoning declarations outrank template heuristics", async (t) => {
  for (const efforts of [[], ["off"], ["none"]]) {
    await t.test(JSON.stringify(efforts), async (t) => {
      const h = await setup(t, { models: advertisedCatalog(efforts), thinking: "medium" });
      h.useLocal();
      await h.emit("session_start");
      assert.equal(h.active.reasoning, false);
      assert.equal(h.thinking, "off");
      assert.deepEqual(getSupportedThinkingLevels(h.active), ["off"]);
      const payload = await capturePayload(h.active, "off");
      assert.equal(payload.reasoning_effort, undefined);
      assert.equal(payload.chat_template_kwargs, undefined);
    });
  }
});

test("catalog context aliases are validated and used before /props", async (t) => {
  for (const [fields, expected] of [
    [{ meta: { n_ctx: 64000 }, context_length: 128000 }, 64000],
    [{ context_length: 128000 }, 128000],
    [{ context_length: 0, max_model_len: 96000 }, 96000],
    [{ context_length: "invalid", meta: { context_length: 48000 } }, 48000],
    [{ context_length: -1, max_model_len: 1.5 }, 8192],
  ]) {
    await t.test(JSON.stringify(fields), async (t) => {
      const h = await setup(t, {
        models: advertisedCatalog(["off", "on"], "off", fields),
        metadata: () => new Response(null, { status: 404 }),
      });
      h.useLocal();
      await h.emit("session_start");
      assert.equal(h.active.contextWindow, expected);
      assert.equal(h.active.maxTokens, expected);
    });
  }
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
