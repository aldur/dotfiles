import assert from "node:assert/strict";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [extensionPath, piRoot] = process.argv.slice(2);
const { loadExtensions } = await import(pathToFileURL(join(piRoot, "dist/core/extensions/loader.js")));
const { extensions, errors } = await loadExtensions([extensionPath], process.cwd());

assert.deepEqual(errors, []);
assert.equal(extensions.length, 1);
assert.ok(extensions[0].tools.has("subagent"), "Pi must register the subagent tool");
