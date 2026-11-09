import assert from "node:assert/strict";
import childProcess from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { mock } from "node:test";
import { pathToFileURL } from "node:url";

// Use Pi's session startup code without a model request in child processes.
if (process.argv[2] === "--mode") {
  assert.equal(process.env.PI_SUBAGENT_WORKER, "1");
  const root = process.env.PI_SUBAGENT_CHECK_ROOT;
  const { parseArgs } = await import(pathToFileURL(join(root, "dist/cli/args.js")));
  const { createSessionManager } = await import(pathToFileURL(join(root, "dist/main.js")));
  const args = parseArgs(process.argv.slice(2));
  assert.deepEqual(args.diagnostics, []);
  assert.deepEqual(args.extensions ?? [], JSON.parse(process.env.DOTFILES_PI_EXTENSIONS ?? "[]"));
  assert.equal(args.noSession, undefined);
  const session = await createSessionManager(args, process.cwd());
  assert.deepEqual(session.getEntries(), [], "Children must start without parent messages");
  session.appendSessionInfo(args.name);
  session.appendMessage({ role: "user", content: args.messages[0], timestamp: Date.now() });
  const { loadExtensions } = await import(pathToFileURL(join(root, "dist/core/extensions/loader.js")));
  const { extensions, errors } = await loadExtensions([process.env.PI_SUBAGENT_CHECK_EXTENSION], process.cwd());
  assert.deepEqual(errors, []);
  assert.ok(extensions[0].handlers.has("before_provider_request"));
  session.appendCustomEntry("invocation", {
    model: args.model,
    thinking: args.thinking,
    tools: args.tools,
    prompt: args.appendSystemPrompt?.map((file) => readFileSync(file, "utf8")).join("\n"),
    description: extensions[0].tools.get("subagent").definition.description,
  });
  process.exit(0);
}

const [extensionPath, piRoot] = process.argv.slice(2);
const root = mkdtempSync(join(tmpdir(), "pi-subagent-check-"));
process.env.PI_CODING_AGENT_DIR = join(root, "agent");
delete process.env.PI_CODING_AGENT_SESSION_DIR;
process.env.PI_SUBAGENT_CHECK_ROOT = piRoot;
process.env.PI_SUBAGENT_CHECK_EXTENSION = extensionPath;
process.env.DOTFILES_PI_EXTENSIONS = JSON.stringify([extensionPath, join(root, "extension with spaces.ts")]);
const { loadExtensions } = await import(pathToFileURL(join(piRoot, "dist/core/extensions/loader.js")));
const { SessionManager } = await import(pathToFileURL(join(piRoot, "dist/core/session-manager.js")));
const starts = [];
const spawn = childProcess.spawn;
mock.method(childProcess, "spawn", (...args) => {
  // Measure dispatch in the parent. Child startup time varies with system load.
  starts.push(performance.now());
  return spawn(...args);
});
syncBuiltinESMExports();
const { extensions, errors } = await loadExtensions([extensionPath], process.cwd());

assert.deepEqual(errors, []);
assert.equal(extensions.length, 1);
assert.ok(extensions[0].tools.has("subagent"), "Pi must register the subagent tool");
assert.equal(extensions[0].flags.get("agent").type, "string");
assert.ok(!extensions[0].handlers.has("before_provider_request"), "Parent requests must keep their retry policy");
for (const event of ["session_start", "model_select", "thinking_level_select"]) {
  assert.ok(!extensions[0].handlers.has(event), "Parent sessions must keep their environment");
}

async function loadWithArgs(args) {
  const original = process.argv;
  try {
    process.argv = [...original.slice(0, 2), ...args];
    return await loadExtensions([extensionPath], process.cwd());
  } finally {
    process.argv = original;
  }
}

try {
  mock.timers.enable({ apis: ["setTimeout"] });
  syncBuiltinESMExports();
  process.env.PI_SUBAGENT_WORKER = "1";
  const worker = await loadExtensions([extensionPath], process.cwd());
  delete process.env.PI_SUBAGENT_WORKER;
  assert.deepEqual(worker.errors, []);
  const workerContext = {
    model: { provider: "test", id: "worker" },
    thinkingLevel: "high",
    sessionManager: { getSessionId: () => "worker-session" },
  };
  const environmentKeys = ["PI_MODEL", "PI_THINKING", "PI_SESSION"];
  const previousEnvironment = environmentKeys.map((key) => process.env[key]);
  const emit = async (name, event = {}, ctx = workerContext) => worker.extensions[0].handlers.get(name)?.[0](event, ctx);
  const failed = (errorMessage) => emit("message_end", {
    message: { role: "assistant", stopReason: "error", errorMessage },
  });
  try {
    process.env.PI_MODEL = "parent/model";
    process.env.PI_THINKING = "low";
    process.env.PI_SESSION = "parent-session";
    await emit("session_start");
    assert.deepEqual(environmentKeys.map((key) => process.env[key]), ["test/worker", "high", "worker-session"]);
    const changedModel = { ...workerContext, model: { provider: "other", id: "org/model" }, thinkingLevel: "medium" };
    await emit("model_select", { model: changedModel.model }, changedModel);
    assert.deepEqual(environmentKeys.map((key) => process.env[key]), ["other/org/model", "medium", "worker-session"]);
    await emit("thinking_level_select", { level: "max" }, { ...changedModel, thinkingLevel: "max" });
    assert.deepEqual(environmentKeys.map((key) => process.env[key]), ["other/org/model", "max", "worker-session"]);
    await emit("session_start", {}, { ...workerContext, model: undefined });
    assert.equal(process.env.PI_MODEL, undefined, "A worker without a model must clear the inherited model");

    async function checkDelay(ms) {
      let done = false;
      const request = emit("before_provider_request").then(() => { done = true; });
      if (ms) {
        mock.timers.tick(ms - 1);
        await Promise.resolve();
        assert.equal(done, false, "The retry must wait for its delay");
        mock.timers.tick(1);
      }
      await request;
      assert.equal(done, true);
    }
    await checkDelay(0);
    for (const ms of [10_000, 20_000, 40_000, 60_000, 60_000]) {
      await failed("HTTP 429: Too Many Requests");
      await checkDelay(ms);
    }
    await emit("message_end", { message: { role: "assistant", stopReason: "stop" } });
    await checkDelay(0);
    await failed("rate_limit_exceeded");
    await checkDelay(10_000);
    await failed("401: Invalid API key");
    await checkDelay(0);
    await failed("429");
    const controller = new AbortController();
    const cancelled = emit("before_provider_request", {}, { signal: controller.signal });
    controller.abort();
    await assert.rejects(cancelled, { name: "AbortError" });
    await emit("session_start");
    await checkDelay(0);
  } finally {
    environmentKeys.forEach((key, index) => {
      if (previousEnvironment[index] === undefined) delete process.env[key];
      else process.env[key] = previousEnvironment[index];
    });
    mock.timers.reset();
    syncBuiltinESMExports();
  }

  const agentsDir = join(process.env.PI_CODING_AGENT_DIR, "agents");
  mkdirSync(agentsDir, { recursive: true });
  for (const name of ["scout", "worker"]) {
    const model = name === "worker" ? "model: test/frontmatter\n" : "";
    writeFileSync(join(agentsDir, `${name}.md`), `---\nname: ${name}\ndescription: Test agent\n${model}---\n`);
  }
  const parent = SessionManager.create(root);
  parent.appendMessage({ role: "user", content: "Parent task", timestamp: Date.now() });
  const execute = extensions[0].tools.get("subagent").definition.execute;
  const ctx = { cwd: root, sessionManager: parent, model: { provider: "test", id: "parent" }, thinkingLevel: "high" };
  const tasks = [
    { agent: "scout", task: "Find the code" },
    { agent: "worker", task: "Change the code" },
  ];
  const startupTasks = [...tasks, ...Array.from({ length: 3 }, (_, index) => ({
    agent: "worker", task: `Queued task ${index}`,
  }))];
  const result = await execute("parallel", { tasks: startupTasks }, undefined, undefined, ctx);
  assert.ok(result.details.results.every((child) => child.exitCode === 0), JSON.stringify(result));
  const sessions = await SessionManager.list(root);
  const children = sessions.filter((session) => session.parentSessionPath === parent.getSessionFile());
  assert.equal(children.length, startupTasks.length);
  assert.equal(starts.length, startupTasks.length);
  for (let index = 1; index < starts.length; index++) {
    assert.ok(starts[index] - starts[index - 1] >= 1400,
      `Worker start interval: ${starts[index] - starts[index - 1]} ms`);
  }
  assert.deepEqual(children.map((session) => session.name).sort(),
    startupTasks.map((task) => `subagent:${task.agent}`).sort());
  for (const child of children) {
    const task = startupTasks.find((task) => child.firstMessage === `Task: ${task.task}`);
    assert.ok(task);
    assert.equal(child.name, `subagent:${task.agent}`);
  }
  assert.equal(parent.getEntries().length, 1, "The parent transcript must stay unchanged");

  const cancelled = new AbortController();
  cancelled.abort();
  const sessionCount = (await SessionManager.list(root)).length;
  await assert.rejects(execute("cancelled", { tasks }, cancelled.signal, undefined, ctx), { name: "AbortError" });
  assert.equal((await SessionManager.list(root)).length, sessionCount);

  const child = SessionManager.open(children[0].path);
  const nested = await execute("nested", tasks[0], undefined, undefined, { ...ctx, sessionManager: child });
  assert.equal(nested.details.results[0].exitCode, 0, JSON.stringify(nested));
  const grandchildren = (await SessionManager.list(root)).filter(
    (session) => session.parentSessionPath === child.getSessionFile(),
  );
  assert.equal(grandchildren.length, 1);
  assert.equal(grandchildren[0].name, "subagent:scout");
  delete process.env.DOTFILES_PI_EXTENSIONS;
  const unwrapped = await execute("unwrapped", tasks[0], undefined, undefined, ctx);
  assert.equal(unwrapped.details.results[0].exitCode, 0, JSON.stringify(unwrapped));

  async function checkCall(tool, params, expected, context = ctx) {
    const before = new Set((await SessionManager.list(context.cwd)).map((session) => session.path));
    const result = await tool.execute("options", params, undefined, undefined, context);
    assert.ok(!result.isError, JSON.stringify(result));
    assert.deepEqual(result.details.results.map((child) => child.exitCode), expected.map(() => 0), JSON.stringify(result));
    assert.deepEqual(result.details.results.map((child) => child.model), expected.map((child) => child.model));
    const children = (await SessionManager.list(context.cwd)).filter((session) => !before.has(session.path));
    assert.equal(children.length, expected.length);
    for (const [index, childResult] of result.details.results.entries()) {
      const child = children.find((session) => session.firstMessage === `Task: ${childResult.task}`);
      assert.ok(child, JSON.stringify(children));
      const invocation = SessionManager.open(child.path).getEntries().find((entry) => entry.customType === "invocation").data;
      assert.equal(invocation.model, expected[index].model);
      assert.equal(invocation.thinking, expected[index].thinking);
      if (expected[index].source) assert.equal(childResult.agentSource, expected[index].source);
      if (expected[index].tools) assert.deepEqual(invocation.tools, expected[index].tools);
      if (expected[index].prompt) assert.equal(invocation.prompt?.trim(), expected[index].prompt);
      if (expected[index].description) assert.match(invocation.description, expected[index].description);
    }
  }

  const tool = extensions[0].tools.get("subagent").definition;
  for (const schema of [tool.parameters, tool.parameters.properties.tasks.items, tool.parameters.properties.chain.items]) {
    assert.equal(schema.properties.model.type, "string");
    assert.ok(!schema.required?.includes("model"));
  }
  await checkCall(tool, { tasks }, [
    { model: "test/parent", thinking: "high" },
    { model: "test/frontmatter" },
  ]);
  await checkCall(tool, { ...tasks[1], model: "test/single" }, [{ model: "test/single" }]);
  await checkCall(tool, { ...tasks[0], model: "test/explicit:low" }, [{ model: "test/explicit:low" }]);
  for (const mode of ["tasks", "chain"]) {
    await checkCall(tool, {
      model: "test/call",
      [mode]: [tasks[1], { ...tasks[0], model: "test/item" }],
    }, [{ model: "test/call" }, { model: "test/item" }]);
  }
  await checkCall(tool, tasks[0], [{}], { ...ctx, model: undefined, thinkingLevel: undefined });

  const cliDir = join(root, "CLI agents");
  mkdirSync(cliDir);
  const cliFiles = [join(cliDir, "first.md"), join(cliDir, "second.md"), join(cliDir, "replacement.md")];
  writeFileSync(cliFiles[0], "---\nname: scout\ndescription: CLI scout\nmodel: test/first\n---\nFirst prompt\n");
  writeFileSync(cliFiles[1], "---\nname: extra\ndescription: CLI extra\n---\nExtra prompt\n");
  writeFileSync(cliFiles[2], "---\nname: scout\ndescription: Replacement scout\nmodel: test/replacement\ntools: [read, bash]\n---\nReplacement prompt\n");
  const loaded = await loadWithArgs([
    "--agent", relative(process.cwd(), cliFiles[0]),
    `--agent=${cliFiles[1]}`,
    "--agent", cliFiles[2],
    "--", "--agent", join(root, "ignored.md"),
  ]);
  assert.deepEqual(loaded.errors, []);
  const cliTool = loaded.extensions[0].tools.get("subagent").definition;
  assert.match(cliTool.description, /extra \(cli\): CLI extra/);
  assert.match(cliTool.description, /scout \(cli\): Replacement scout/);
  assert.doesNotMatch(cliTool.description, /CLI scout/);
  const replacement = {
    model: "test/replacement", source: "cli", tools: ["read", "bash"], prompt: "Replacement prompt",
    description: /extra \(cli\): CLI extra/,
  };
  await checkCall(cliTool, { tasks: [tasks[0], { agent: "extra", task: "Extra task" }, tasks[1]] }, [
    replacement,
    { model: "test/parent", thinking: "high", source: "cli", prompt: "Extra prompt" },
    { model: "test/frontmatter", source: "user" },
  ]);
  await checkCall(cliTool, { ...tasks[0], model: "test/override" }, [{ ...replacement, model: "test/override" }]);
  const projectDir = join(root, ".pi", "agents");
  mkdirSync(projectDir, { recursive: true });
  writeFileSync(join(projectDir, "scout.md"), "---\nname: scout\ndescription: Project scout\nmodel: test/project\n---\n");
  for (const agentScope of ["project", "both"]) {
    await checkCall(cliTool, { ...tasks[0], agentScope }, [replacement]);
  }
  const otherCwd = join(root, "other");
  mkdirSync(otherCwd);
  await checkCall(cliTool, { ...tasks[0], cwd: otherCwd }, [replacement], { ...ctx, cwd: otherCwd });

  const invalid = join(cliDir, "invalid.md");
  writeFileSync(invalid, "---\nname: 123\ndescription: Invalid agent\n---\n");
  for (const [args, message] of [
    [["--agent"], /--agent requires a Markdown file path/],
    [["--agent="], /--agent requires a Markdown file path/],
    [["--agent", "--model", "test/model"], /--agent requires a Markdown file path/],
    [["--agent", join(root, "missing.md")], /missing\.md/],
    [["--agent", invalid], /name and description must be strings/],
  ]) {
    const failed = await loadWithArgs(args);
    assert.equal(failed.errors.length, 1);
    assert.match(failed.errors[0].error, message);
  }
} finally {
  mock.restoreAll();
  syncBuiltinESMExports();
  rmSync(root, { recursive: true, force: true });
}
