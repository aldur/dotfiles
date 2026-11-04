import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

// Pi reuses the module when it creates an extension instance for another session.
let stash = "";

export default function (pi: ExtensionAPI) {
  const updateStatus = (ctx: ExtensionContext) => {
    ctx.ui.setStatus("pi-prompt-stash", stash ? "Prompt stashed (Ctrl+S)" : undefined);
  };

  pi.registerShortcut("ctrl+s", {
    description: "Stash or restore the prompt; swap if both contain text",
    handler(ctx) {
      if (ctx.mode !== "tui") return;
      const draft = ctx.ui.getEditorText();
      ctx.ui.setEditorText(stash);
      stash = draft;
      updateStatus(ctx);
    },
  });

  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode === "tui") updateStatus(ctx);
  });
}
