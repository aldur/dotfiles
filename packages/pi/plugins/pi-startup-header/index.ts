import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode === "tui") {
      ctx.ui.setHeader(() => ({
        render: () => [],
        invalidate() {},
      }));
    }
  });
}
