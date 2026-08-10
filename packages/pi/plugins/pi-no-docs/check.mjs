// Build-time check for the pi-no-docs extension (see default.nix).
// Loads stripDocsBlock from index.ts and buildSystemPrompt from the
// pinned pi, then verifies that the strip changes the default prompt.
// Node strips the type-only import in index.ts, so no dependencies.
import { pathToFileURL } from "node:url";

const [indexPath, promptModulePath] = process.argv.slice(2);
const load = (path) => import(pathToFileURL(path).href);

const { stripDocsBlock } = await load(indexPath);
const { buildSystemPrompt } = await load(promptModulePath);

if (stripDocsBlock(buildSystemPrompt({ cwd: "/" })) === null) {
  console.error(
    "pi-no-docs: stripDocsBlock does not match pi's default prompt; update index.ts",
  );
  process.exit(1);
}
