import assert from "node:assert/strict";
import { createRequire, registerHooks } from "node:module";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

const [extensionPath, piRoot, statuslinePath] = process.argv.slice(2);
const requirePi = createRequire(join(piRoot, "package.json"));
const tuiUrl = pathToFileURL(requirePi.resolve("@earendil-works/pi-tui")).href;
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "@earendil-works/pi-tui") {
      return nextResolve(tuiUrl, context);
    }
    return nextResolve(specifier, context);
  },
});
const { default: extension } = await import(pathToFileURL(extensionPath));
const { default: statusline } = await import(pathToFileURL(statuslinePath));
const { TuiMainScreen } = await import("@earendil-works/pi-tui");
const { FooterDataProvider } = await import(pathToFileURL(join(piRoot, "dist/core/footer-data-provider.js")));
const { runAgentLoop } = await import(pathToFileURL(join(
  piRoot, "node_modules/@earendil-works/pi-agent-core/dist/agent-loop.js",
)));
const { streamSimple } = await import(pathToFileURL(join(
  piRoot, "node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js",
)));

function setup(t) {
	let now = 1000;
	t.mock.method(performance, "now", () => now);
  const handlers = new Map();
  const statuses = [];
  let status;
  const ctx = {
    mode: "tui",
    model: {
      id: "local-model", provider: "llama-cpp", api: "openai-completions",
      baseUrl: "http://localhost:8080/v1", reasoning: true, input: ["text"],
      contextWindow: 32768, maxTokens: 8192,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    },
    isIdle: () => false,
    ui: {
      theme: { fg: (_color, text) => text },
      setStatus(key, text) {
        assert.equal(key, "pi-throughput");
        status = text;
        statuses.push(text);
      },
    },
  };
  extension({ on: (name, handler) => handlers.set(name, handler) });
  const emit = (name, event = {}) => handlers.get(name)?.(event, ctx);
  t.after(() => emit("session_shutdown"));
  const payload = { model: ctx.model.id, stream: true, messages: [] };
  return {
    ctx, emit, statuses, payload,
    advance: (ms) => { now += ms; },
    end: (fields = {}) => emit("message_end", { message: {
      role: "assistant", provider: ctx.model.provider, model: ctx.model.id,
      stopReason: "stop", usage: { input: 0, cacheWrite: 0, output: 0 }, ...fields,
    } }),
    delta(type, delta, usage) {
      return emit("message_update", {
        message: { role: "assistant", provider: ctx.model.provider, model: ctx.model.id, usage },
        assistantMessageEvent: { type, delta },
      });
    },
    get status() { return status; },
    start: () => emit("before_provider_request", { payload }),
    chunk(data, fields = {}) {
      now += 200;
      return emit("provider_stream_event", {
        api: ctx.model.api, provider: ctx.model.provider, model: ctx.model.id, data, ...fields,
      });
    },
  };
}

const progress = { total: 10000, cache: 9000, processed: 9500, time_ms: 500 };
const timings = {
  cache_n: 9000, prompt_n: 1000, prompt_ms: 800, prompt_per_second: 1250,
  predicted_n: 35, predicted_ms: 700, predicted_per_second: 50,
};

test("only streaming, interactive llama.cpp requests get the extra fields", (t) => {
  for (const provider of ["llama-cpp", "llama.cpp"]) {
    const h = setup(t);
    h.ctx.model.provider = provider;
    const original = structuredClone(h.payload);
    assert.deepEqual(h.start(), { ...original, return_progress: true, timings_per_token: true });
    assert.deepEqual(h.payload, original, "preserve the original request and its other settings");
  }
  for (const change of [
    (h) => { h.ctx.mode = "print"; },
    (h) => { h.ctx.mode = "rpc"; },
    (h) => { h.ctx.isIdle = () => true; },
    (h) => { h.payload.stream = false; },
    (h) => { h.payload.model = "routed-model"; },
  ]) {
    const h = setup(t);
    change(h);
    assert.equal(h.start(), undefined);
    h.chunk({ timings });
    assert.equal(h.status, undefined);
  }
});

test("live prefill excludes the cached prefix; final server speeds persist", (t) => {
  const h = setup(t);
  h.start();
  h.chunk({ prompt_progress: progress });
  assert.equal(h.status, "prefill:1000.0 tok/s 50%");
  h.chunk({ timings });
  assert.equal(h.status, "prefill:1250.0 tok/s | decode:50.0 tok/s");
  h.emit("message_end", { message: { role: "toolResult" } });
  const count = h.statuses.length;
  h.chunk({ timings });
  assert.equal(h.statuses.length, count, "unchanged data does not repaint the footer");
  h.end();
  h.emit("agent_end");
  h.chunk({ timings: { ...timings, predicted_per_second: 999 } });
  assert.equal(h.status, "prefill:1250.0 tok/s | decode:50.0 tok/s");
  h.start();
  assert.equal(h.status, undefined, "each tool-loop request starts fresh");
});

test("zero duration, fully cached prompts, and count/duration timings", (t) => {
  const h = setup(t);
  h.start();
  h.chunk({ prompt_progress: { ...progress, processed: 9000, time_ms: 0 } });
  assert.equal(h.status, "prefill:… 0%");
  h.chunk({ prompt_progress: { ...progress, processed: 10000, cache: 10000, time_ms: 0 } });
  assert.equal(h.status, "prefill:cached 100%");
  h.chunk({ timings: { prompt_n: 0, predicted_n: 20, predicted_ms: 500 } });
  assert.equal(h.status, "prefill:cached | decode:40.0 tok/s");
  h.start();
  h.chunk({ timings: { prompt_n: 500, prompt_ms: 250, predicted_n: 20, predicted_ms: 500 } });
  assert.equal(h.status, "prefill:2000.0 tok/s | decode:40.0 tok/s");
});

test("malformed chunks and chunks for another request cannot corrupt speeds", (t) => {
  const h = setup(t);
  h.start();
  for (const data of [
    null, [], "unexpected", { prompt_progress: {} },
    { prompt_progress: { ...progress, cache: -1 } },
    { prompt_progress: { ...progress, processed: 10001 } },
    { prompt_progress: { ...progress, total: NaN } },
    { timings: { prompt_per_second: Infinity, predicted_per_second: -1 } },
  ]) h.chunk(data);
  assert.equal(h.status, undefined);
  h.chunk({ timings }, { provider: "other-provider" });
  h.chunk({ timings }, { model: "other-model" });
  h.chunk({ timings }, { api: "openai-responses" });
  assert.equal(h.status, undefined);
  h.ctx.signal = AbortSignal.abort();
  h.chunk({ timings });
  assert.equal(h.status, undefined);
});

test("errors, cancellation, model changes and session changes clear stale speeds", (t) => {
  for (const event of ["model_select", "session_start", "session_tree", "session_shutdown"]) {
    const h = setup(t);
    h.start();
    h.chunk({ timings });
    h.emit(event);
    h.chunk({ timings });
    assert.equal(h.status, undefined);
  }
  for (const stopReason of ["aborted", "error"]) {
    const h = setup(t);
    h.start();
    h.chunk({ prompt_progress: progress });
    h.emit("message_end", { message: { role: "assistant", stopReason } });
    assert.equal(h.status, undefined);
  }
});

test("Sushi and mlx-serve timings work under arbitrary provider names", (t) => {
  for (const provider of ["sushi", "mlx-serve", "my-local-server"]) {
    const h = setup(t);
    h.ctx.model.provider = provider;
    assert.equal(h.start(), undefined, "no llama.cpp-specific flags");
    // Their prompt_n includes cached_n, unlike llama.cpp's prompt_n.
    h.chunk({ timings: { ...timings, prompt_n: 10000, cached_n: 9000 } });
    assert.equal(h.status, "prefill:1250.0 tok/s | decode:50.0 tok/s");
    h.end();
    h.start();
    h.chunk({ timings: { prompt_n: 10000, cached_n: 9000, prompt_ms: 800,
      predicted_n: 35, predicted_ms: 700 } });
    assert.equal(h.status, "prefill:1250.0 tok/s | decode:50.0 tok/s");
    h.chunk({ timings: { prompt_n: 10000, cached_n: 10000, prompt_ms: 0,
      prompt_per_second: 0, predicted_per_second: 50 } });
    assert.equal(h.status, "prefill:cached | decode:50.0 tok/s");
  }
});

test("vLLM server decode metrics take precedence over client estimates", (t) => {
  const h = setup(t);
  h.ctx.model.provider = "vllm";
  assert.equal(h.start(), undefined);
  h.advance(400);
  h.delta("text_delta", "Hello");
  h.advance(1000);
  h.delta("text_delta", " world!");
  assert.ok(h.status.includes("decode:~"));
  h.chunk({
    metrics: { tokens_per_second: 10, generation_time_ms: 1980 },
    usage: { completion_tokens: 100 },
  });
  h.advance(1000);
  h.delta("text_delta", "More text");
  h.end({ usage: { input: 800, cacheWrite: 0, output: 100 } });
  assert.equal(h.status, "input/TTFT:~2000.0 tok/s | decode:50.0 tok/s | TTFT:0.40s");
});

test("vLLM overall throughput is never labeled as pure decode", (t) => {
  const h = setup(t);
  h.ctx.model.provider = "vllm";
  h.start();
  h.chunk({ metrics: { tokens_per_second: 50 }, usage: { completion_tokens: 100 } });
  assert.equal(h.status, undefined);
  for (const [generation_time_ms, completion_tokens] of [[0, 100], [100, 1], [-1, 100], [NaN, 100]]) {
    h.chunk({ metrics: { generation_time_ms }, usage: { completion_tokens } });
    assert.equal(h.status, undefined);
  }
});

test("any provider gets labeled client estimates including thinking and tool deltas", (t) => {
  const h = setup(t);
  h.ctx.model.provider = "custom-anthropic";
  h.ctx.model.api = "anthropic-messages";
  assert.equal(h.start(), undefined);
  h.advance(400);
  h.delta("thinking_delta", "Thinking");
  assert.equal(h.status, "decode:… | TTFT:0.40s");
  h.advance(1000);
  h.delta("toolcall_delta", '{"x":42}');
  h.advance(1000);
  h.delta("text_delta", "Response");
  assert.equal(h.status, "decode:~2.0 tok/s | TTFT:0.40s");
  h.end({ usage: { input: 600, cacheWrite: 200, cacheRead: 9000, output: 21 } });
  assert.equal(h.status, "input/TTFT:~2000.0 tok/s | decode:~10.0 tok/s | TTFT:0.40s");
  h.emit("agent_end");
  h.delta("text_delta", "Late text");
  assert.equal(h.status, "input/TTFT:~2000.0 tok/s | decode:~10.0 tok/s | TTFT:0.40s");
});

test("a buffered single output chunk does not invent a decode rate", (t) => {
  const h = setup(t);
  h.ctx.model.provider = "vllm";
  h.start();
  h.advance(1000);
  h.delta("text_delta", "Buffered response");
  h.end({ usage: { input: 500, cacheWrite: 0, output: 50 } });
  assert.equal(h.status, "input/TTFT:~500.0 tok/s | TTFT:1.00s");
});

test("decode updates during thinking and follows recent changes in speed", (t) => {
  const h = setup(t);
  h.ctx.model.provider = "sushi";
  h.start();
  h.advance(400);
  h.delta("thinking_delta", "Thinking");
  assert.equal(h.status, "decode:… | TTFT:0.40s");
  for (let i = 0; i < 2; i++) {
    h.advance(1000);
    h.delta("thinking_delta", "x".repeat(40));
    assert.equal(h.status, "decode:~10.0 tok/s | TTFT:0.40s");
  }
  for (let i = 0; i < 2; i++) {
    h.advance(1000);
    h.delta("text_delta", "slow");
  }
  assert.equal(h.status, "decode:~1.0 tok/s | TTFT:0.40s");
  h.chunk({ timings });
  assert.equal(h.status, "prefill:1250.0 tok/s | decode:50.0 tok/s | TTFT:0.40s");
});

test("prompt usage reported early is shown from the first decoded output", (t) => {
  const h = setup(t);
  h.ctx.model.provider = "custom-anthropic";
  h.start();
  h.advance(400);
  h.delta("thinking_delta", "Thinking", { input: 600, cacheWrite: 200, cacheRead: 9000 });
  assert.equal(h.status, "input/TTFT:~2000.0 tok/s | decode:… | TTFT:0.40s");
});

test("live decoding refreshes through pauses and stops refreshing after completion", (t) => {
  t.mock.timers.enable({ apis: ["setInterval"] });
  const h = setup(t);
  h.start();
  h.advance(400);
  h.delta("text_delta", "Hello");
  h.advance(1000);
  h.delta("text_delta", "x".repeat(40));
  assert.equal(h.status, "decode:~10.0 tok/s | TTFT:0.40s");
  h.advance(2000);
  t.mock.timers.tick(2000);
  assert.equal(h.status, "decode:~0.0 tok/s | TTFT:0.40s");
  h.end({ usage: { input: 800, cacheWrite: 0, output: 11 } });
  assert.equal(h.status, "input/TTFT:~2000.0 tok/s | decode:~10.0 tok/s | TTFT:0.40s");
  const finalCount = h.statuses.length;
  h.advance(10000);
  t.mock.timers.tick(10000);
  assert.equal(h.statuses.length, finalCount);
});

test("live refresh cannot update an aborted or replaced session", (t) => {
  t.mock.timers.enable({ apis: ["setInterval"] });
  for (const event of ["model_select", "session_tree", "session_shutdown", "agent_end"]) {
    const h = setup(t);
    h.start();
    h.advance(400);
    h.delta("text_delta", "Hello");
    h.emit(event);
    const count = h.statuses.length;
    h.advance(10000);
    t.mock.timers.tick(10000);
    assert.equal(h.statuses.length, count);
  }
  const h = setup(t);
  h.start();
  h.advance(400);
  h.delta("text_delta", "Hello");
  h.ctx.signal = AbortSignal.abort();
  const count = h.statuses.length;
  h.advance(10000);
  t.mock.timers.tick(10000);
  assert.equal(h.statuses.length, count);
});

test("Pi's OpenAI adapter sends flags and forwards progress and timing chunks", async (t) => {
  const h = setup(t);
  let request;
  const chunks = [
    { choices: [], prompt_progress: progress },
    { choices: [{ index: 0, delta: { reasoning_content: "Thinking" }, finish_reason: null }], timings },
    { choices: [{ index: 0, delta: { content: "Hello" }, finish_reason: null }] },
    { choices: [{ index: 0, delta: {}, finish_reason: "stop" }], timings,
      usage: { prompt_tokens: 10000, completion_tokens: 35, total_tokens: 10035,
        prompt_tokens_details: { cached_tokens: 9000 } } },
  ];
  const stream = streamSimple(h.ctx.model, {
    messages: [{ role: "user", content: "Hi", timestamp: Date.now() }],
  }, {
    apiKey: "local", maxRetries: 0,
    onPayload: (payload) => h.emit("before_provider_request", { payload }),
    onProviderStreamEvent: (data, model) => h.chunk(data, { model: model.id }),
    fetch: async (_url, init) => {
      request = JSON.parse(init.body);
      const data = chunks.map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`).join("");
      return new Response(`${data}data: [DONE]\n\n`, {
        headers: { "content-type": "text/event-stream" },
      });
    },
  });
  const message = await stream.result();
  assert.equal(message.stopReason, "stop", message.errorMessage);
  assert.equal(request.return_progress, true);
  assert.equal(request.timings_per_token, true);
  assert.ok(h.statuses.includes("prefill:1000.0 tok/s 50%"));
  assert.equal(h.status, "prefill:1250.0 tok/s | decode:50.0 tok/s");
  assert.equal(message.usage.output, 35);
  assert.equal(message.usage.cacheRead, 9000);
  assert.ok(message.content.some((block) => block.type === "thinking"));
  assert.ok(message.content.some((block) => block.type === "text" && block.text === "Hello"));
});

test("the real agent loop paints the footer while its SSE response is still open", async (t) => {
  const h = setup(t);
  h.ctx.model.provider = "sushi";
  const output = [];
  const terminal = {
    columns: 160, rows: 24, kittyProtocolActive: false,
    start() {}, stop() {}, write: (text) => output.push(text),
    hideCursor() {}, showCursor() {}, clearLine() {}, clearFromCursor() {},
    clearScreen() {}, moveBy() {}, setTitle() {}, setProgress() {}, setProgramStatus() {},
  };
  const tui = new TuiMainScreen(terminal);
  const footerData = new FooterDataProvider("/");
  const setStatus = h.ctx.ui.setStatus;
  h.ctx.ui.setStatus = (key, text) => {
    setStatus(key, text);
    footerData.setExtensionStatus(key, text);
    tui.requestRender();
  };
  h.ctx.getContextUsage = () => ({ tokens: 0, percent: 0, contextWindow: 32768 });
  h.ctx.sessionManager = { getCwd: () => "/", getBranch: () => [] };
  let footer;
  h.ctx.ui.setFooter = (factory) => {
    footer = factory(tui, h.ctx.ui.theme, footerData);
    tui.addChild(footer);
  };
  let startFooter;
  statusline({
    getThinkingLevel: () => "medium",
    on: (name, handler) => { if (name === "session_start") startFooter = handler; },
  });
  await startFooter({}, h.ctx);
  tui.start();
  t.after(() => { tui.stop(); footer.dispose(); footerData.dispose(); });

  let controller;
  let finished = false;
  const encoder = new TextEncoder();
  const body = new ReadableStream({ start(value) { controller = value; } });
  const send = (chunk) => controller.enqueue(encoder.encode(`data: ${JSON.stringify(chunk)}\n\n`));
  const thinking = (text) => ({ choices: [{ index: 0, delta: { reasoning_content: text }, finish_reason: null }] });
  const response = runAgentLoop([
    { role: "user", content: "Hi", timestamp: Date.now() },
  ], { messages: [], tools: [] }, {
    model: h.ctx.model, apiKey: "local", convertToLlm: (messages) => messages,
  }, (event) => h.emit(event.type, event), undefined, (model, context, options) => streamSimple(model, context, {
    ...options, maxRetries: 0,
    onPayload: (payload) => h.emit("before_provider_request", { payload }),
    onProviderStreamEvent: (data) => h.chunk(data),
    fetch: async () => {
      h.advance(400);
      send(thinking("Thinking"));
      return new Response(body, { headers: { "content-type": "text/event-stream" } });
    },
  })).then((messages) => { finished = true; return messages; });
  t.after(async () => { if (!finished) controller.close(); await response; });

  await t.waitFor(() => assert.match(output.join(""), /decode:…/), { interval: 10, timeout: 2000 });
  output.length = 0;
  h.advance(1000);
  send(thinking("x".repeat(40)));
  await t.waitFor(() => assert.match(output.join(""), /decode:~/), { interval: 10, timeout: 2000 });
  assert.equal(finished, false, "the footer must update before the server finishes");
  assert.ok(footer.render(160)[1].includes("TTFT:"));

  send({ choices: [{ index: 0, delta: { content: "Hello" }, finish_reason: null }] });
  send({ choices: [{ index: 0, delta: {}, finish_reason: "stop" }] });
  send({ choices: [], timings, usage: { prompt_tokens: 10000, completion_tokens: 35,
    prompt_tokens_details: { cached_tokens: 9000 } } });
  controller.enqueue(encoder.encode("data: [DONE]\n\n"));
  controller.close();
  const messages = await response;
  assert.equal(messages.at(-1).stopReason, "stop");
  assert.ok(footer.render(160)[1].includes("decode:50.0 tok/s"));
});
