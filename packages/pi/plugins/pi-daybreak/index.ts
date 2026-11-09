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
  let lastRequest: string | undefined;
  let requestProgram: string | undefined;
  let responseProgram: string | undefined;
  let mismatchReported = false;

  const resetRequest = () => {
    lastRequest = undefined;
    requestProgram = undefined;
    responseProgram = undefined;
    mismatchReported = false;
  };
  const status = (ctx: ExtensionContext) => {
    const label = mode === "default" ? "default (no override)" : `${mode} (requested)`;
    const response = responseProgram === undefined ? "" : `; last response: ${responseProgram}`;
    return `Daybreak: ${label}${supportsDaybreak(ctx) ? response : "; inactive on this provider"}`;
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
        ctx.ui.notify([
          status(ctx),
          lastRequest ?? "No supported provider request observed for the current model.",
          `Response access_programs.cyber: ${responseProgram ?? "not reported"}`,
        ].join("\n"), "info");
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
    resetRequest();
    updateStatus(ctx);
  });
  pi.on("model_select", (_event, ctx) => {
    resetRequest();
    updateStatus(ctx);
  });
  pi.on("before_provider_request", (event, ctx) => {
    resetRequest();
    updateStatus(ctx);
    if (!supportsDaybreak(ctx)) return;
    const body = event.payload as Record<string, unknown>;
    const payload = mode === "default" ? body : {
      ...body,
      access_programs: {
        ...(body.access_programs as Record<string, unknown> | undefined),
        // Omission can use the account default, so off must send standard.
        cyber: mode === "off" ? "standard" : `daybreak_${mode}`,
      },
    };
    const program = (payload.access_programs as Record<string, unknown> | undefined)?.cyber;
    requestProgram = typeof program === "string" ? program : undefined;
    lastRequest = `Last prepared request: ${ctx.model?.provider}/${body.model ?? ctx.model?.id} (${ctx.model?.api}); access_programs.cyber=${program ?? "omitted"}`;
    if (mode !== "default") return payload;
  });
  pi.on("provider_stream_event", (event, ctx) => {
    if (!lastRequest) return;
    const data = event.data as { response?: { access_programs?: { cyber?: unknown } | null } } | null;
    const programs = data?.response?.access_programs;
    if (programs === null) responseProgram = "null";
    else if (typeof programs?.cyber === "string") responseProgram = programs.cyber;
    else return;
    updateStatus(ctx);
    const effectiveProgram = responseProgram === "null" ? "standard" : responseProgram;
    if (requestProgram && requestProgram !== effectiveProgram && !mismatchReported) {
      mismatchReported = true;
      ctx.ui.notify(`Daybreak: requested ${requestProgram}, but the server reported ${effectiveProgram}. The requested program was not applied.`, "warning");
    }
  });
}
