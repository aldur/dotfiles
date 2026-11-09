import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { zstdDecompressSync } from "node:zlib";

const [extensionPath, piRoot] = process.argv.slice(2);
const load = (path) => import(pathToFileURL(join(piRoot, path)));
const { loadExtensions } = await load("dist/core/extensions/loader.js");
const { stream } = await load("node_modules/@earendil-works/pi-ai/dist/api/openai-codex-responses.js");
const { stream: streamResponses } = await load("node_modules/@earendil-works/pi-ai/dist/api/openai-responses.js");

async function setup() {
  const { extensions, errors } = await loadExtensions([extensionPath], process.cwd());
  assert.deepEqual(errors, []);
  const extension = extensions[0];
  const command = extension.commands.get("daybreak");
  assert.ok(command);
  const notices = [];
  let status;
  let choice;
  const ctx = {
    mode: "tui",
    model: {
      id: "gpt-6-sol", provider: "openai-codex", api: "openai-codex-responses",
      baseUrl: "https://chatgpt.com/backend-api", reasoning: true,
      input: ["text"], contextWindow: 272000, maxTokens: 128000,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    },
    ui: {
      setStatus(key, value) { assert.equal(key, "pi-daybreak"); status = value; },
      notify(text, level) { notices.push({ text, level }); },
      select: async (_title, options) => choice === undefined ? undefined : options[choice],
    },
  };
  const emit = async (name, event = {}) => extension.handlers.get(name)?.[0](event, ctx);
  return {
    ctx, notices, command, emit,
    get status() { return status; },
    run: (args) => command.handler(args, ctx),
    menu: (index) => { choice = index; return command.handler("", ctx); },
    request: (payload = { model: "gpt-6-sol" }) => emit("before_provider_request", { payload }),
  };
}

test("default preserves requests; off sets standard and preserves other fields", async () => {
  const h = await setup();
  assert.equal(await h.request(), undefined);
  await h.run("blue");
  const payload = { model: "gpt-6-sol", input: [], access_programs: { other: "keep", cyber: "old" } };
  const original = structuredClone(payload);
  assert.deepEqual(await h.request(payload), { ...payload, access_programs: { other: "keep", cyber: "daybreak_blue" } });
  assert.deepEqual(payload, original);
  await h.run("off");
  assert.equal((await h.request()).access_programs.cyber, "standard");
  await h.run("default");
  assert.equal(await h.request(), undefined);
  assert.equal(h.status, undefined);
});

test("toggle and on restore the last tier; session changes reset it", async () => {
  const h = await setup();
  for (const [action, expected] of [
    ["toggle", "daybreak_blue"], ["toggle", "standard"], ["red", "daybreak_red"],
    ["off", "standard"], ["on", "daybreak_red"], ["toggle", "standard"], ["toggle", "daybreak_red"],
  ]) {
    await h.run(action);
    assert.equal((await h.request()).access_programs.cyber, expected);
  }
  assert.match(h.status, /red \(requested\)/);
  await h.emit("session_start", { reason: "resume" });
  assert.equal(await h.request(), undefined);
  await h.run("on");
  assert.equal((await h.request()).access_programs.cyber, "daybreak_blue");
});

test("menu cancellation, status, and invalid input do not change the selection", async () => {
  const h = await setup();
  await h.menu(1);
  assert.equal((await h.request()).access_programs.cyber, "daybreak_red");
  await h.menu(undefined);
  await h.run("status");
  await h.run("blue red");
  assert.equal(h.notices.at(-1).level, "error");
  assert.equal((await h.request()).access_programs.cyber, "daybreak_red");
  assert.deepEqual(h.command.getArgumentCompletions("bl"), [{ value: "blue", label: "blue" }]);
  assert.equal(h.command.getArgumentCompletions("invalid"), null);
  h.ctx.mode = "rpc";
  await h.run("");
  assert.match(h.notices.at(-1).text, /red/);
});

test("other providers are unchanged; the footer follows provider switches", async () => {
  const h = await setup();
  await h.run("blue");
  for (const [provider, api] of [
    ["anthropic", "anthropic-messages"],
    ["openai", "openai-completions"],
    ["openai-compatible", "openai-responses"],
  ]) {
    Object.assign(h.ctx.model, { provider, api });
    await h.emit("model_select");
    assert.match(h.status, /inactive/);
    assert.equal(await h.request(), undefined);
  }
  for (const [provider, api] of [
    ["openai", "openai-responses"],
    ["openai-codex", "openai-codex-responses"],
  ]) {
    Object.assign(h.ctx.model, { provider, api });
    await h.emit("model_select");
    assert.doesNotMatch(h.status, /inactive/);
    assert.equal((await h.request()).access_programs.cyber, "daybreak_blue");
  }
  h.ctx.model = undefined;
  await h.emit("model_select");
  assert.match(h.status, /inactive/);
  assert.equal(await h.request(), undefined);
  const other = await setup();
  assert.equal(await other.request(), undefined);
});

test("status distinguishes the selection, prepared request, and reported program", async () => {
  const h = await setup();
  Object.assign(h.ctx.model, { provider: "openai", api: "openai-responses" });
  await h.run("blue");
  await h.run("status");
  assert.match(h.notices.at(-1).text, /No supported provider request observed/);
  await h.request();
  await h.run("red");
  await h.run("status");
  assert.match(h.notices.at(-1).text, /red \(requested\)/);
  assert.match(h.notices.at(-1).text, /Last prepared request: openai\/gpt-6-sol \(openai-responses\); access_programs.cyber=daybreak_blue/);
  assert.match(h.notices.at(-1).text, /Response access_programs.cyber: not reported/);
  await h.emit("provider_stream_event", { data: { response: { access_programs: { cyber: "daybreak_blue" } } } });
  await h.emit("provider_stream_event", { data: { type: "response.output_text.delta", delta: "Hello" } });
  await h.run("status");
  assert.match(h.notices.at(-1).text, /Response access_programs.cyber: daybreak_blue/);
  assert.match(h.status, /red \(requested\); last response: daybreak_blue/);
  assert.equal(h.notices.filter((notice) => notice.level === "warning").length, 0);
  await h.request();
  await h.run("status");
  assert.match(h.notices.at(-1).text, /Response access_programs.cyber: not reported/);
  await h.emit("session_start", { reason: "reload" });
  await h.run("status");
  assert.match(h.notices.at(-1).text, /No supported provider request observed/);
});

test("a server program mismatch updates the footer and warns once per request", async () => {
  const h = await setup();
  Object.assign(h.ctx.model, { provider: "openai", api: "openai-responses" });
  await h.run("blue");
  await h.request();
  for (const type of ["response.created", "response.in_progress", "response.completed"]) {
    await h.emit("provider_stream_event", { data: { type, response: { access_programs: { cyber: "standard" } } } });
  }
  assert.match(h.status, /blue \(requested\); last response: standard/);
  const warnings = () => h.notices.filter((notice) => notice.level === "warning");
  assert.equal(warnings().length, 1);
  assert.match(warnings()[0].text, /requested daybreak_blue, but the server reported standard/);
  await h.request();
  assert.doesNotMatch(h.status, /last response/);
  await h.emit("provider_stream_event", { data: { response: { access_programs: null } } });
  assert.equal(warnings().length, 2);
  assert.match(warnings()[1].text, /server reported standard/);
  await h.run("off");
  await h.request();
  await h.emit("provider_stream_event", { data: { response: { access_programs: null } } });
  assert.equal(warnings().length, 2);
  await h.emit("model_select");
  assert.doesNotMatch(h.status, /last response/);
  await h.emit("provider_stream_event", { data: { response: { access_programs: { cyber: "daybreak_blue" } } } });
  assert.doesNotMatch(h.status, /last response/);
  assert.equal(warnings().length, 2);
});

const claims = Buffer.from(JSON.stringify({ "https://api.openai.com/auth": { chatgpt_account_id: "test" } })).toString("base64url");
for (const [name, provider, api, baseUrl, apiKey, transport] of [
  ["Codex", "openai-codex", "openai-codex-responses", "https://chatgpt.com/backend-api", `test.${claims}.test`, stream],
  ["OpenAI ChatGPT", "openai", "openai-responses", "https://api.openai.com/v1", "test-chatgpt-token", streamResponses],
  ["OpenAI API key", "openai", "openai-responses", "https://api.openai.com/v1", "sk-test", streamResponses],
]) {
  test(`the ${name} HTTP transport sends each selected program`, async () => {
    const h = await setup();
    Object.assign(h.ctx.model, { provider, api, baseUrl });
    for (const [action, program] of [["blue", "daybreak_blue"], ["red", "daybreak_red"], ["off", "standard"], ["default", undefined]]) {
      await h.run(action);
      let body;
      const result = await transport(h.ctx.model, {
        messages: [{ role: "user", content: "Hello", timestamp: 0 }],
      }, {
        apiKey, transport: "sse", maxRetries: 0,
        onPayload: (payload) => h.request(payload),
        onProviderStreamEvent: (data) => h.emit("provider_stream_event", { data, provider, api, model: h.ctx.model.id }),
        fetch: async (_url, init) => {
          const bytes = new Headers(init.headers).get("content-encoding") === "zstd"
            ? zstdDecompressSync(init.body).toString() : init.body;
          body = JSON.parse(bytes);
          const response = {
            type: "response.completed",
            response: {
              status: "completed", output: [],
              access_programs: program ? { cyber: program } : null,
              usage: { input_tokens: 0, output_tokens: 0, total_tokens: 0 },
            },
          };
          return new Response(`data: ${JSON.stringify(response)}\n\n`, {
            headers: { "content-type": "text/event-stream" },
          });
        },
      }).result();
      assert.equal(result.stopReason, "stop", result.errorMessage);
      assert.equal(body.access_programs?.cyber, program);
      await h.run("status");
      assert.ok(h.notices.at(-1).text.includes(`access_programs.cyber=${program ?? "omitted"}`));
      assert.ok(h.notices.at(-1).text.includes(`Response access_programs.cyber: ${program ?? "null"}`));
      assert.equal(h.notices.filter((notice) => notice.level === "warning").length, 0);
    }
  });
}
