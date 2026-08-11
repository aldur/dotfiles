/**
 * /system-prompt: show the current system prompt.
 *
 * The command opens the prompt in the ephemeral multi-line editor and
 * discards the result. It writes nothing to the session, so the
 * conversation and the LLM context stay clean.
 *
 * pi applies extension changes (for example pi-no-docs) when a turn
 * starts. Before the first turn the command shows the base prompt.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("system-prompt", {
    description: "Show the current system prompt (not saved to the session)",
    handler: async (_args, ctx) => {
      await ctx.ui.editor("System prompt (view only, edits are discarded)", ctx.getSystemPrompt());
    },
  });
}
