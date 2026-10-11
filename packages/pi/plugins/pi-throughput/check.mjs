import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

const [extensionPath, piRoot] = process.argv.slice(2);
const { default: extension } = await import(pathToFileURL(extensionPath));
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
  const payload = { model: ctx.model.id, stream: true, messages: [] };
  return {
    ctx, emit, statuses, payload,
    advance: (ms) => { now += ms; },
    end: (fields = {}) => emit("message_end", { message: {
      role: "assistant", provider: ctx.model.provider, model: ctx.model.id,
      stopReason: "stop", usage: { input: 0, cacheWrite: 0, output: 0 }, ...fields,
    } }),
    delta(type, delta) {
      return emit("message_update", {
        message: { role: "assistant", provider: ctx.model.provider, model: ctx.model.id },
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
  assert.equal(h.status, "TTFT:0.40s");
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
