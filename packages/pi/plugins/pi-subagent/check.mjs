import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

// Use Pi's session startup code without a model request in child processes.
if (process.argv[2] === "--mode") {
  const root = process.env.PI_SUBAGENT_CHECK_ROOT;
  const { parseArgs } = await import(pathToFileURL(join(root, "dist/cli/args.js")));
  const { createSessionManager } = await import(pathToFileURL(join(root, "dist/main.js")));
  const args = parseArgs(process.argv.slice(2));
  assert.deepEqual(args.diagnostics, []);
  assert.equal(args.noSession, undefined);
  const session = await createSessionManager(args, process.cwd());
  assert.deepEqual(session.getEntries(), [], "Children must start without parent messages");
  session.appendSessionInfo(args.name);
  session.appendMessage({ role: "user", content: args.messages[0], timestamp: Date.now() });
  process.exit(0);
}

const [extensionPath, piRoot] = process.argv.slice(2);
const root = mkdtempSync(join(tmpdir(), "pi-subagent-check-"));
process.env.PI_CODING_AGENT_DIR = join(root, "agent");
delete process.env.PI_CODING_AGENT_SESSION_DIR;
process.env.PI_SUBAGENT_CHECK_ROOT = piRoot;
const { loadExtensions } = await import(pathToFileURL(join(piRoot, "dist/core/extensions/loader.js")));
const { SessionManager } = await import(pathToFileURL(join(piRoot, "dist/core/session-manager.js")));
const { extensions, errors } = await loadExtensions([extensionPath], process.cwd());

assert.deepEqual(errors, []);
assert.equal(extensions.length, 1);
assert.ok(extensions[0].tools.has("subagent"), "Pi must register the subagent tool");

try {
  const agentsDir = join(process.env.PI_CODING_AGENT_DIR, "agents");
  mkdirSync(agentsDir, { recursive: true });
  for (const name of ["scout", "worker"]) {
    writeFileSync(join(agentsDir, `${name}.md`), `---\nname: ${name}\ndescription: Test agent\n---\n`);
  }
  const parent = SessionManager.create(root);
  parent.appendMessage({ role: "user", content: "Parent task", timestamp: Date.now() });
  const execute = extensions[0].tools.get("subagent").definition.execute;
  const ctx = { cwd: root, sessionManager: parent };
  const tasks = [
    { agent: "scout", task: "Find the code" },
    { agent: "worker", task: "Change the code" },
  ];
  const result = await execute("parallel", { tasks }, undefined, undefined, ctx);
  assert.ok(result.details.results.every((child) => child.exitCode === 0), JSON.stringify(result));
  const sessions = await SessionManager.list(root);
  const children = sessions.filter((session) => session.parentSessionPath === parent.getSessionFile());
  assert.equal(children.length, 2);
  assert.deepEqual(children.map((session) => session.name).sort(), ["subagent:scout", "subagent:worker"]);
  for (const child of children) {
    const task = tasks.find((task) => child.name === `subagent:${task.agent}`);
    assert.equal(child.firstMessage, `Task: ${task.task}`);
  }
  assert.equal(parent.getEntries().length, 1, "The parent transcript must stay unchanged");

  const child = SessionManager.open(children[0].path);
  const nested = await execute("nested", tasks[0], undefined, undefined, { ...ctx, sessionManager: child });
  assert.equal(nested.details.results[0].exitCode, 0, JSON.stringify(nested));
  const grandchildren = (await SessionManager.list(root)).filter(
    (session) => session.parentSessionPath === child.getSessionFile(),
  );
  assert.equal(grandchildren.length, 1);
  assert.equal(grandchildren[0].name, "subagent:scout");
} finally {
  rmSync(root, { recursive: true, force: true });
}
