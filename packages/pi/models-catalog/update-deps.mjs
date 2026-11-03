import { readFile, writeFile } from "node:fs/promises";

const [lockPath, nixPath = "packages/pi/models-catalog/default.nix"] = process.argv.slice(2);
if (!lockPath) throw new Error("Expected the upstream bun.lock path");
const lock = Bun.JSON5.parse(await readFile(lockPath, "utf8"));
let nix = await readFile(nixPath, "utf8");
for (const name of ["remeda", "zod"]) {
  const [id, , , hash] = lock.packages[name] ?? [];
  if (typeof id !== "string" || !id.startsWith(`${name}@`) ||
      typeof hash !== "string" || !hash.startsWith("sha512-")) {
    throw new Error(`Invalid ${name} entry in bun.lock`);
  }
  const pattern = new RegExp(`(${name} = \\{\\s*version = ")[^"]+(";\\s*hash = ")[^"]+(";)`);
  if (!pattern.test(nix)) throw new Error(`Missing ${name} pin in ${nixPath}`);
  nix = nix.replace(pattern, (_match, before, middle, after) =>
    `${before}${id.slice(name.length + 1)}${middle}${hash}${after}`);
}
await writeFile(nixPath, nix);
