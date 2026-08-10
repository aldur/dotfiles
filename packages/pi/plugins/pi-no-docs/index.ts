/**
 * Remove the "Pi documentation" block from the default system prompt.
 *
 * The default prompt points the model at pi's own docs in the store
 * (dist/core/system-prompt.js). The section costs tokens on every turn
 * and only helps when the user works on pi itself.
 *
 * Two guards call the same stripDocsBlock below, so the anchor lives in
 * one place:
 * - check.mjs (run by default.nix) applies it to the default prompt of
 *   the pinned pi at build time;
 * - this extension throws when the default prompt has no block to strip
 *   (a self-updated pi can drift from the nix pin). pi catches the
 *   throw, shows "Extension error", and continues the run.
 * A custom system prompt (--system-prompt, SYSTEM.md) has no block by
 * design, so that case stays silent.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// The block is one "Pi documentation (...)" header line and its "- "
// bullet lines. The match stops at the first line that is not a bullet,
// so upstream can reword the bullets without breaking it.
const PI_DOCS_BLOCK = /\n\nPi documentation \([^\n]*(?:\n- [^\n]*)*/;

/** Return the prompt without the docs block, or null when no match. */
export function stripDocsBlock(prompt: string): string | null {
  const stripped = prompt.replace(PI_DOCS_BLOCK, "");
  return stripped === prompt ? null : stripped;
}

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", (event) => {
    const stripped = stripDocsBlock(event.systemPrompt);
    if (stripped !== null) {
      return { systemPrompt: stripped };
    }
    if (!event.systemPromptOptions.customPrompt) {
      throw new Error(
        "pi-no-docs: the default prompt has no docs block; the upstream wording changed",
      );
    }
  });
}
