// Build-time check for the pi-no-docs extension (see default.nix).
// Loads stripDocsBlock from index.ts and buildSystemPrompt from the
// pinned pi, then verifies removal of docs without changing other sections.
// Node strips the type-only import in index.ts, so no dependencies.
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const [indexPath, promptModulePath] = process.argv.slice(2);
const load = (path) => import(pathToFileURL(path).href);

const { default: extension, stripDocsBlock } = await load(indexPath);
const { buildSystemPrompt, buildSystemPromptSections } = await load(promptModulePath);

const options = {
  cwd: "/",
  appendSystemPrompt: "Keep this addendum.\n- Keep its bullet too.",
  contextFiles: [{ path: "/AGENTS.md", content: "Keep these project instructions." }],
};
const prompt = buildSystemPrompt(options);
const stripped = stripDocsBlock(prompt);
if (stripped === null) {
  console.error(
    "pi-no-docs: stripDocsBlock does not match pi's default prompt; update index.ts",
  );
  process.exit(1);
}

assert.ok(!stripped.includes("Pi documentation ("));
assert.ok(!stripped.includes("<docs>") && !stripped.includes("</docs>"));
assert.ok(stripped.includes(options.appendSystemPrompt));
assert.ok(stripped.includes(options.contextFiles[0].content));
if (buildSystemPromptSections) {
  const sections = buildSystemPromptSections(options);
  const expected = Object.entries(sections)
    .filter(([name]) => name !== "docs")
    .map(([, content]) => content)
    .join("\n\n");
  assert.equal(stripped, expected, "Only the docs section should be removed");
}

// Guard the plain-text format too: the wrapper can run an older user install.
const docs = "Pi documentation (read only for pi):\n- Main documentation: /README.md\n- Examples: /examples";
const prefix = "Keep these instructions.";
const suffix = "\n\nKeep this section.\n- Keep this bullet.";
for (const block of [docs, `<docs>\n${docs}\n</docs>`]) {
  for (const tail of ["", suffix]) {
    assert.equal(stripDocsBlock(`${prefix}\n\n${block}${tail}`), prefix + tail);
  }
}
assert.equal(stripDocsBlock(prefix + suffix), null);
assert.equal(stripDocsBlock(stripped), null);

// Exercise the registered hook as well as its strip helper.
let beforeAgentStart;
extension({
  on(name, handler) {
    assert.equal(name, "before_agent_start");
    beforeAgentStart = handler;
  },
});
assert.deepEqual(
  beforeAgentStart({ systemPrompt: prompt, systemPromptOptions: options }),
  { systemPrompt: stripped },
);
assert.equal(
  beforeAgentStart({
    systemPrompt: prefix,
    systemPromptOptions: { customPrompt: prefix },
  }),
  undefined,
);
assert.throws(
  () => beforeAgentStart({ systemPrompt: prefix, systemPromptOptions: {} }),
  /the default prompt has no docs block/,
);
console.log("pi-no-docs: prompt formats, section preservation, and extension hook passed");
