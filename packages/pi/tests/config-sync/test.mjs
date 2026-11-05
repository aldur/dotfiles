import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import * as fs from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";

const { syncConfig, migrateExtensions } = await import(pathToFileURL(process.env.PI_CONFIG_SYNC_MODULE));
const piPackage = process.env.PI_CONFIG_SYNC_PACKAGE;
const { SettingsManager } = await import(pathToFileURL(join(piPackage, "dist/core/settings-manager.js")));
const { KeybindingsManager } = await import(pathToFileURL(join(piPackage, "dist/core/keybindings.js")));
const lockfile = createRequire(join(piPackage, "package.json"))("proper-lockfile");
const read = (path) => JSON.parse(fs.readFileSync(path, "utf8"));
const write = (path, value) => fs.writeFileSync(path, JSON.stringify(value));
function fixture(t) {
  const dir = fs.mkdtempSync(join(tmpdir(), "pi-config-test-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

test("MCP settings preserve other servers and remain writable", async (t) => {
  const dir = fixture(t);
  const path = join(dir, "mcp.json");
  const other = { command: "/local/server", env: { TOKEN: "fixture" } };
  write(path, { mcpServers: { other, browser: { enabled: false } } });
  const browser = { command: "/nix/store/browser/bin/mcp", exposure: "codemode" };
  await syncConfig({ mcp: { mcpServers: { browser } } }, dir);
  assert.deepEqual(read(path), { mcpServers: { other, browser: { enabled: false, ...browser } } });
  assert.equal(fs.statSync(path).mode & 0o777, 0o600);
});

test("both writable files preserve undeclared values and load in Pi", async (t) => {
  const dir = fixture(t);
  const settings = join(dir, "settings.json");
  const bindings = join(dir, "keybindings.json");
  write(settings, { tuiMode: "fullscreen", theme: "dark", compaction: { enabled: false, keepRecentTokens: 1234 } });
  write(bindings, { "tui.editor.cursorUp": ["ctrl+k"], "app.session.new": ["ctrl+alt+n"] });
  const managed = {
    settings: { tuiMode: "regular", compaction: { keepRecentTokens: 4000 } },
    keybindings: { "tui.editor.cursorUp": ["up", "ctrl+p"] },
  };
  await syncConfig(managed, dir);
  assert.deepEqual(read(settings), { tuiMode: "regular", theme: "dark", compaction: { enabled: false, keepRecentTokens: 4000 } });
  assert.deepEqual(read(bindings), { "tui.editor.cursorUp": ["up", "ctrl+p"], "app.session.new": ["ctrl+alt+n"] });
  assert.equal(SettingsManager.create(dir, dir).getTuiMode(), "regular");
  assert.deepEqual(KeybindingsManager.create(dir).getEffectiveConfig()["tui.editor.cursorUp"], ["up", "ctrl+p"]);
  const before = [settings, bindings].map((path) => fs.statSync(path, { bigint: true }));
  for (const stat of before) assert.equal(stat.mode & 0o777n, 0o600n);
  await syncConfig(managed, dir);
  await syncConfig({ settings: {}, keybindings: {} }, dir);
  for (const [i, path] of [settings, bindings].entries()) {
    assert.equal(fs.statSync(path, { bigint: true }).mtimeNs, before[i].mtimeNs);
    assert.equal(fs.statSync(path).ino, Number(before[i].ino));
  }
});

test("fresh home and the previous Nix keybindings symlink", async (t) => {
  const dir = join(fixture(t), "agent");
  await syncConfig({ settings: { tuiMode: "regular" } }, dir);
  const bindings = join(dir, "keybindings.json");
  fs.symlinkSync(process.env.PI_CONFIG_SYNC_LEGACY, bindings);
  await syncConfig({ keybindings: { "tui.editor.cursorUp": ["up", "ctrl+p"] } }, dir);
  assert.equal(fs.lstatSync(bindings).isSymbolicLink(), false);
  assert.deepEqual(read(bindings)["app.session.new"], ["ctrl+alt+n"]);
  assert.deepEqual(read(process.env.PI_CONFIG_SYNC_LEGACY)["tui.editor.cursorUp"], ["up"]);
});

test("malformed JSON and non-object files survive a failed merge", async (t) => {
  const dir = fixture(t);
  for (const name of ["settings", "keybindings", "mcp"]) {
    const path = join(dir, `${name}.json`);
    for (const text of ["{invalid", "[]", "null", "", '{}\n{}']) {
      fs.writeFileSync(path, text);
      await assert.rejects(syncConfig({ [name]: {} }, dir));
      assert.equal(fs.readFileSync(path, "utf8"), text);
      assert.equal(fs.existsSync(`${path}.lock`), false);
    }
  }
  assert.equal(fs.readdirSync(dir).some((name) => name.startsWith(".pi-config-")), false);
});

test("unmanaged symlinks are left intact", async (t) => {
  const dir = fixture(t);
  const original = join(dir, "user-config.json");
  write(original, { theme: "dark" });
  const link = join(dir, "settings.json");
  fs.symlinkSync(original, link);
  await assert.rejects(syncConfig({ settings: { tuiMode: "regular" } }, dir), /non-Nix symlink/);
  assert.equal(fs.lstatSync(link).isSymbolicLink(), true);
  assert.deepEqual(read(original), { theme: "dark" });
});

test("waits for Pi's own settings writer and preserves its update", async (t) => {
  const dir = fixture(t);
  const settings = join(dir, "settings.json");
  write(settings, { tuiMode: "fullscreen" });
  const child = spawn(process.execPath, ["--input-type=module", "-e", `
    import { writeSync } from "node:fs";
    import { FileSettingsStorage } from ${JSON.stringify(pathToFileURL(join(piPackage, "dist/core/settings-manager.js")).href)};
    new FileSettingsStorage(${JSON.stringify(dir)}, ${JSON.stringify(dir)}).withLock("global", (current) => {
      writeSync(1, "locked\\n");
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 300);
      return JSON.stringify({ ...JSON.parse(current), theme: "light", packages: ["saved-by-pi"] });
    });
  `], { stdio: ["ignore", "pipe", "inherit"] });
  t.after(() => { if (child.exitCode === null) child.kill(); });
  const exited = once(child, "exit");
  const [chunk] = await once(child.stdout, "data");
  assert.match(chunk.toString(), /locked/);
  await syncConfig({ settings: { tuiMode: "regular" } }, dir);
  assert.equal((await exited)[0], 0);
  assert.deepEqual(read(settings), { tuiMode: "regular", theme: "light", packages: ["saved-by-pi"] });
});

test("a busy Pi lock fails without changing the file or stealing the lock", async (t) => {
  const dir = fixture(t);
  const path = join(dir, "settings.json");
  write(path, { theme: "dark" });
  const release = await lockfile.lock(path, { realpath: false });
  try {
    await assert.rejects(syncConfig({ settings: { tuiMode: "regular" } }, dir), { code: "ELOCKED" });
    assert.deepEqual(read(path), { theme: "dark" });
    assert.equal(await lockfile.check(path, { realpath: false }), true);
  } finally {
    await release();
  }
});

test("migration removes legacy managed paths and preserves user extensions", async (t) => {
  const dir = fixture(t);
  const path = join(dir, "settings.json");
  await migrateExtensions(join(dir, "missing"));
  assert.equal(fs.existsSync(join(dir, "missing")), false);
  const store = `/nix/store/${"0".repeat(32)}-`;
  const user = [
    "./user.ts", "~/extensions/custom.ts",
    `${store}unrelated-1.0/index.ts`,
    `${store}pi-subagent-custom/index.ts`,
    `${store}pi-subagent-1.4.0/other.ts`,
    "/tmp/pi-subagent-1.4.0/index.ts",
  ];
  const legacy = [
    "pi-llama-0-unstable-2026-10-30", "pi-no-docs", "pi-startup-header",
    "pi-openai-discovery", "pi-statusline", "pi-subagent-1.4.0",
    "pi-system-prompt", "pi-throughput",
  ].map((name) => `${store}${name}/index.ts`);
  write(path, { extensions: [...legacy, ...user], theme: "dark", packages: ["npm:user-package"] });
  await migrateExtensions(dir);
  assert.deepEqual(read(path), { extensions: user, theme: "dark", packages: ["npm:user-package"] });
  const before = fs.statSync(path, { bigint: true }).mtimeNs;
  await migrateExtensions(dir);
  assert.equal(fs.statSync(path, { bigint: true }).mtimeNs, before);
  await syncConfig({ settings: { extensions: ["./declared.ts", ...legacy] } }, dir);
  assert.deepEqual(read(path).extensions, ["./declared.ts"]);
});
