import * as fs from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const require = createRequire("@piPackage@/package.json");
const lockfile = require("proper-lockfile");
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

function parseObject(text, path) {
  const value = JSON.parse(text.replace(/^\uFEFF/, ""));
  if (!isObject(value)) throw new Error(`${path}: expected a JSON object`);
  return value;
}

// Nix owns only the declared keys. Objects merge recursively; arrays replace.
function merge(current, managed) {
  return {
    ...current,
    ...Object.fromEntries(Object.entries(managed).map(([key, value]) => [
      key,
      isObject(value) && isObject(current[key]) ? merge(current[key], value) : value,
    ])),
  };
}

async function syncFile(path, managed) {
  // Match Pi's realpath:false lock, including for files that do not exist yet.
  // Read after acquiring it so another Pi session's latest writes are preserved.
  const release = await lockfile.lock(path, {
    realpath: false,
    retries: { retries: 30, minTimeout: 100, maxTimeout: 100 },
  });
  try {
    let info;
    try {
      info = fs.lstatSync(path);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    if (info?.isSymbolicLink()) {
      // Migrate the old Home Manager symlink without modifying its target.
      if (!fs.realpathSync(path).startsWith("/nix/store/")) {
        throw new Error(`${path}: refusing to replace a non-Nix symlink`);
      }
    } else if (info && !info.isFile()) {
      throw new Error(`${path}: expected a regular file`);
    }
    const original = info ? fs.readFileSync(path, "utf8") : undefined;
    const current = original === undefined ? {} : parseObject(original, path);
    const next = merge(current, managed);
    if (info?.isFile() && (info.mode & 0o777) === 0o600 &&
        JSON.stringify(current) === JSON.stringify(next)) return;

    const temporary = fs.mkdtempSync(join(dirname(path), ".pi-config-"));
    try {
      const staged = join(temporary, "config.json");
      fs.writeFileSync(staged, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 });
      fs.renameSync(staged, path);
    } finally {
      fs.rmSync(temporary, { recursive: true, force: true });
    }
  } finally {
    await release();
  }
}

export async function syncConfig(managed, agentDir) {
  if (!isObject(managed)) throw new Error("managed configuration must be a JSON object");
  for (const [name, value] of Object.entries(managed)) {
    if (!["settings", "keybindings"].includes(name) || !isObject(value)) {
      throw new Error(`invalid managed configuration: ${name}`);
    }
  }
  const directory = resolve(agentDir);
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  for (const [name, value] of Object.entries(managed)) {
    await syncFile(join(directory, `${name}.json`), value);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (process.argv.length !== 4) throw new Error("usage: pi-config-sync MANAGED_JSON AGENT_DIR");
    const [managedPath, agentDir] = process.argv.slice(2);
    await syncConfig(parseObject(fs.readFileSync(managedPath, "utf8"), managedPath), agentDir);
  } catch (error) {
    console.error(`pi-config-sync: ${error.message}`);
    process.exitCode = 1;
  }
}
