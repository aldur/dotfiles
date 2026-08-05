// Delete node_modules entries not reachable from the app's declared
// `dependencies` (see slim.nix). Vendored installs routinely unpack the
// whole workspace lockfile — webpack, typescript, react — next to the
// handful of packages the shipped server actually requires.
//
// Usage: node prune-node-modules.js <app-dir>
const fs = require("fs");
const path = require("path");

const app = process.argv[2];
const nm = path.join(app, "node_modules");

const keep = new Set();
const stack = Object.keys(
  JSON.parse(fs.readFileSync(path.join(app, "package.json"), "utf8"))
    .dependencies || {},
);
while (stack.length > 0) {
  const name = stack.pop();
  if (keep.has(name)) continue;
  keep.add(name);
  const pj = path.join(nm, name, "package.json");
  if (!fs.existsSync(pj)) continue;
  const p = JSON.parse(fs.readFileSync(pj, "utf8"));
  // Peer and optional dependencies resolve at runtime too, when installed.
  for (const dep of [
    ...Object.keys(p.dependencies || {}),
    ...Object.keys(p.optionalDependencies || {}),
    ...Object.keys(p.peerDependencies || {}),
  ])
    stack.push(dep);
}

const rm = (p) => fs.rmSync(p, { recursive: true, force: true });
for (const entry of fs.readdirSync(nm)) {
  if (entry.startsWith(".")) continue; // .bin: dangling links die at fixup
  if (entry.startsWith("@")) {
    for (const sub of fs.readdirSync(path.join(nm, entry)))
      if (!keep.has(`${entry}/${sub}`)) rm(path.join(nm, entry, sub));
    if (fs.readdirSync(path.join(nm, entry)).length === 0)
      rm(path.join(nm, entry));
  } else if (!keep.has(entry)) rm(path.join(nm, entry));
}
console.log(`prune-node-modules: kept ${keep.size} packages`);
