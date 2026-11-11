import assert from "node:assert/strict";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { test } from "node:test";

const [extensionPath, piRoot] = process.argv.slice(2);
const { default: extension } = await import(pathToFileURL(extensionPath));
const aiRoot = join(piRoot, "node_modules/@earendil-works/pi-ai/dist");
const { getSupportedThinkingLevels } = await import(pathToFileURL(join(aiRoot, "models.js")));
const { streamSimple } = await import(pathToFileURL(join(aiRoot, "api/openai-completions.js")));

async function setup(t, rows, profile = "privatemode-ai", status = 200) {
  const env = { ...process.env };
  t.after(() => { for (const key of ["PI_OPENAI_BASE_URL", "PI_OPENAI_API_KEY", "PI_OPENAI_PROFILE"]) {
    if (env[key] === undefined) delete process.env[key]; else process.env[key] = env[key];
  } });
  process.env.PI_OPENAI_BASE_URL = "http://localhost:8080/v1/";
  process.env.PI_OPENAI_API_KEY = "test-key";
  process.env.PI_OPENAI_PROFILE = profile;
  const registrations = [];
  const events = new Map();
  const requests = [];
  let result = { rows, status };
  t.mock.method(console, "warn", () => {});
  t.mock.method(globalThis, "fetch", async (url, init) => {
    requests.push({ url, init });
    return Response.json({ data: result.rows }, { status: result.status });
  });
  await extension({ registerProvider: (id, provider) => registrations.push({ id, ...provider }), on: (name, fn) => events.set(name, fn) });
  return { registrations, requests, emit: (text) => events.get("input")({ text }), setResult: (rows, status) => { result = { rows, status }; } };
}

async function payload(model, level) {
  let body;
  await streamSimple({ ...model, provider: "openai-compatible", api: "openai-completions", baseUrl: "http://localhost:8080/v1" },
    { messages: [{ role: "user", content: "test", timestamp: 0 }] }, {
      apiKey: "test", reasoning: level === "off" ? undefined : level,
      onPayload: (value) => { body = value; throw new Error("captured"); },
    }).result();
  return body;
}

test("Privatemode discovery combines its catalog and model tasks", async (t) => {
  const h = await setup(t, [
    { id: "glm-5.3-flash", tasks: ["generate", "tool_calling", "vision"] },
    { id: "qwen3-embedding-4b", tasks: ["embed"] },
  ]);
  assert.equal(h.requests[0].url, "http://localhost:8080/v1/models");
  assert.equal(h.requests[0].init.headers.Authorization, "Bearer test-key");
  assert.equal(h.registrations.length, 1);
  const [model] = h.registrations[0].models;
  assert.equal(h.registrations[0].models.length, 1);
  assert.equal(model.contextWindow, 1000000);
  assert.equal(model.maxTokens, 131072);
  assert.deepEqual(model.input, ["text", "image"]);
  assert.deepEqual(getSupportedThinkingLevels(model), ["low", "high", "max"]);
  for (const [level, expected] of [["low", "low"], ["high", "high"], ["max", "max"]]) {
    assert.equal((await payload(model, level)).reasoning_effort, expected);
  }
});

test("generic models use advertised data and conservative fallback", async (t) => {
  const h = await setup(t, [
    { id: "known", context_length: 64000, max_output_tokens: 4096, architecture: { input_modalities: ["text", "image"] }, reasoning: true, reasoning_efforts: ["none", "low", "high"] },
    { id: "unknown" },
  ], "");
  const [known, unknown] = h.registrations[0].models;
  assert.equal(known.contextWindow, 64000);
  assert.equal(known.maxTokens, 4096);
  assert.deepEqual(known.input, ["text", "image"]);
  assert.equal((await payload(known, "off")).reasoning_effort, "none");
  assert.equal(unknown.contextWindow, 8192);
  assert.equal(unknown.reasoning, false);
});

test("refresh updates models and keeps the last catalog after failure", async (t) => {
  const h = await setup(t, [{ id: "one" }], "");
  h.setResult([{ id: "two" }], 200);
  await h.emit("/model");
  assert.equal(h.registrations.at(-1).models[0].id, "two");
  h.setResult([], 503);
  await h.emit("/model");
  assert.equal(h.registrations.length, 2);
});
