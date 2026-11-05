import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

const [extensionPath, piRoot] = process.argv.slice(2);
const load = (path) => import(pathToFileURL(join(piRoot, path)));
const { loadExtensions, loadExtensionsCached, clearExtensionCache } = await load("dist/core/extensions/loader.js");
const { CustomEditor } = await load("dist/modes/interactive/components/custom-editor.js");
const { KeybindingsManager } = await load("dist/core/keybindings.js");
const { ExtensionRunner } = await load("dist/core/extensions/runner.js");
const { matchesKey } = await load("node_modules/@earendil-works/pi-tui/dist/index.js");

async function setup(loader = loadExtensions) {
  const { extensions, errors, runtime } = await loader([extensionPath], process.cwd());
  assert.deepEqual(errors, []);
  const extension = extensions[0];
  const keybindings = new KeybindingsManager();
  const runner = new ExtensionRunner(extensions, runtime, process.cwd());
  const shortcuts = runner.getShortcuts(keybindings.getEffectiveConfig());
  assert.deepEqual(runner.getShortcutDiagnostics(), []);
  const shortcut = shortcuts.get("alt+s");
  assert.ok(shortcut);
  const editor = new CustomEditor({ requestRender() {} }, { borderColor: (s) => s }, keybindings);
  let status;
  const ctx = {
    mode: "tui",
    ui: {
      getEditorText: () => editor.getExpandedText(),
      setEditorText: (text) => editor.setText(text),
      setStatus(key, value) {
        assert.equal(key, "pi-prompt-stash");
        status = value;
      },
    },
  };
  editor.onExtensionShortcut = (data) => {
    if (!matchesKey(data, "alt+s")) return false;
    shortcut.handler(ctx);
    return true;
  };
  return {
    editor, ctx, keybindings,
    press: () => editor.handleInput("\x1bs"),
    get status() { return status; },
    start: () => extension.handlers.get("session_start")[0]({ type: "session_start" }, ctx),
  };
}

test("Alt+S preserves pasted text, whitespace, and both drafts during a swap", async () => {
  const h = await setup();
  h.press();
  assert.equal(h.editor.getText(), "");
  assert.equal(h.status, undefined);
  const draft = "  Draft α\n".repeat(30) + "\n";
  h.editor.handleInput(`\x1b[200~${draft}\x1b[201~`);
  assert.equal(h.editor.getExpandedText(), draft);
  h.press();
  assert.equal(h.editor.getText(), "");
  assert.match(h.status, /Alt\+S/);
  h.editor.setText("Second draft");
  h.press();
  assert.equal(h.editor.getExpandedText(), draft);
  h.press();
  assert.equal(h.editor.getText(), "Second draft");
  h.editor.setText("");
  h.press();
  assert.equal(h.editor.getExpandedText(), draft);
  assert.equal(h.status, undefined);
});

test("the stash survives session changes, but a fresh extension starts empty", async () => {
  clearExtensionCache();
  const h = await setup(loadExtensionsCached);
  h.editor.setText("Keep this draft");
  h.press();
  const next = await setup(loadExtensionsCached);
  next.start();
  assert.match(next.status, /stashed/);
  next.press();
  assert.equal(next.editor.getText(), "Keep this draft");
  next.press();
  clearExtensionCache();
  const fresh = await setup(loadExtensionsCached);
  fresh.start();
  fresh.press();
  assert.equal(fresh.editor.getText(), "");
  assert.equal(fresh.status, undefined);
});

test("non-terminal modes leave drafts alone and picker bindings remain available", async () => {
  const h = await setup();
  for (const mode of ["print", "rpc"]) {
    h.ctx.mode = mode;
    h.editor.setText("Keep this draft");
    h.press();
    h.start();
    assert.equal(h.editor.getText(), "Keep this draft");
    assert.equal(h.status, undefined);
  }
  for (const action of ["app.models.save", "app.thinking.save", "app.session.toggleSort"]) {
    assert.ok(h.keybindings.matches("\x13", action));
  }
});
