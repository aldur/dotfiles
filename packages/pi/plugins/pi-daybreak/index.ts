import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type Mode = "default" | "off" | "blue" | "red";
const actions = ["blue", "red", "on", "off", "toggle", "default", "status"];
const choices = {
  "Blue — request Daybreak Blue": "blue",
  "Red — request Daybreak Red": "red",
  "Off — request standard safeguards": "off",
  "Default — leave the request unchanged": "default",
} as const;

const supportsDaybreak = (ctx: ExtensionContext) =>
  ctx.model?.provider === "openai-codex" ||
  (ctx.model?.provider === "openai" && ctx.model.api === "openai-responses");

export default function (pi: ExtensionAPI) {
  let mode: Mode = "default";
  let lastTier: "blue" | "red" = "blue";

  const status = (ctx: ExtensionContext) => {
    const label = mode === "default" ? "default (no override)" : `${mode} (requested)`;
    return `Daybreak: ${label}${supportsDaybreak(ctx) ? "" : "; inactive on this provider"}`;
  };
  const updateStatus = (ctx: ExtensionContext) => {
    ctx.ui.setStatus("pi-daybreak", mode === "default" ? undefined : status(ctx));
  };

  pi.registerCommand("daybreak", {
    description: "Select Daybreak Blue, Red, or standard safeguards for openai and openai-codex",
    getArgumentCompletions(prefix) {
      const matches = actions.filter((action) => action.startsWith(prefix));
      return matches.length ? matches.map((value) => ({ value, label: value })) : null;
    },
    async handler(args, ctx) {
      let action = args.trim().toLowerCase();
      if (!action && ctx.mode === "tui") {
        const choice = await ctx.ui.select(status(ctx), Object.keys(choices));
        if (!choice) return;
        action = choices[choice as keyof typeof choices];
      }
      if (!action || action === "status") {
        ctx.ui.notify(status(ctx), "info");
        return;
      }
      switch (action) {
        case "blue":
        case "red":
          mode = lastTier = action;
          break;
        case "on":
          mode = lastTier;
          break;
        case "toggle":
          mode = mode === "blue" || mode === "red" ? "off" : lastTier;
          break;
        case "off":
        case "default":
          mode = action;
          break;
        default:
          ctx.ui.notify(`Usage: /daybreak [${actions.join("|")}]`, "error");
          return;
      }
      updateStatus(ctx);
      ctx.ui.notify(status(ctx), "info");
    },
  });

  pi.on("session_start", (_event, ctx) => {
    mode = "default";
    lastTier = "blue";
    updateStatus(ctx);
  });
  pi.on("model_select", (_event, ctx) => updateStatus(ctx));
  pi.on("before_provider_request", (event, ctx) => {
    if (mode === "default" || !supportsDaybreak(ctx)) return;
    const body = event.payload as Record<string, unknown>;
    return {
      ...body,
      access_programs: {
        ...(body.access_programs as Record<string, unknown> | undefined),
        // Omission can use the account default, so off must send standard.
        cyber: mode === "off" ? "standard" : `daybreak_${mode}`,
      },
    };
  });
}
