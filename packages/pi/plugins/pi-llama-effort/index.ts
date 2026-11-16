import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { Api, Model } from "@earendil-works/pi-ai";

const PROVIDER_ID = "llama.cpp";
const PROPS_TIMEOUT_MS = 5_000;

// Qwen 3.8 accepts low, medium and xhigh. Other models may use different
// values. Check the template, since model names can be aliases.
export function hasQwenEffortLevels(template: string): boolean {
	if (!template.includes("enable_thinking")) return false;
	const match = template.match(
		/\b(?:resolved_)?reasoning_effort\s+not\s+in\s*(?:\(([^)]*)\)|\[([^\]]*)\])/,
	);
	if (!match) return false;
	const values = (match[1] ?? match[2]).split(",").map((value) => value.trim()).filter(Boolean);
	return values.length === 3 && ["low", "medium", "xhigh"].every(
		(level) => values.includes(`"${level}"`) || values.includes(`'${level}'`),
	);
}

// Show the three supported levels. Pi's max sends xhigh.
function applyEffortLevels(model: Model<Api>): void {
	model.thinkingLevelMap = { minimal: null, high: null, max: "xhigh" };
	model.compat = {
		...model.compat,
		thinkingFormat: "chat-template",
		chatTemplateKwargs: {
			enable_thinking: { $var: "thinking.enabled" },
			preserve_thinking: true,
			reasoning_effort: { $var: "thinking.effort", omitWhenOff: true },
		},
	};
}

async function readTemplate(model: Model<Api>, ctx: ExtensionContext): Promise<string | undefined> {
	const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
	if (!auth.ok) throw new Error(auth.error);
	const url = new URL(`${model.baseUrl.replace(/\/v1\/?$/, "")}/props`);
	url.searchParams.set("model", model.id);
	const response = await fetch(url, {
		headers: { ...auth.headers, ...(auth.apiKey && { Authorization: `Bearer ${auth.apiKey}` }) },
		signal: AbortSignal.timeout(PROPS_TIMEOUT_MS),
	});
	if (!response.ok) throw new Error(`HTTP ${response.status}`);
	const props = await response.json();
	return typeof props?.chat_template === "string" ? props.chat_template : undefined;
}

export default function (pi: ExtensionAPI) {
	// Change the selected model in place. Pi reads its thinking levels and
	// request format from this object.
	async function upgrade(model: Model<Api> | undefined, ctx: ExtensionContext): Promise<void> {
		// The built-in provider sets reasoning only after it reads a template
		// with enable_thinking. Thus other models do not get a /props request.
		if (model?.provider !== PROVIDER_ID || !model.reasoning) return;
		if (model.compat?.thinkingFormat === "chat-template") return;
		try {
			const template = await readTemplate(model, ctx);
			if (template && hasQwenEffortLevels(template)) applyEffortLevels(model);
		} catch (error) {
			ctx.ui.notify(`[llama.cpp] cannot read effort levels of ${model.id}: ${(error as Error).message}`, "warning");
		}
	}

	pi.on("session_start", (_event, ctx) => upgrade(ctx.model, ctx));
	pi.on("model_select", (event, ctx) => upgrade(event.model, ctx));
}
