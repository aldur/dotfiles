import { readFileSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const CATALOG_PATH = "@catalogPath@";
const PROVIDER = "openai-compatible";
const LEVELS = ["off", "minimal", "low", "medium", "high", "xhigh", "max"] as const;
type Level = typeof LEVELS[number];
type Entry = Record<string, any>;

function positive(...values: unknown[]): number | undefined {
	return values.find((v): v is number => typeof v === "number" && Number.isSafeInteger(v) && v > 0);
}

function modelFrom(entry: Entry, known: Entry | undefined, profile: string) {
	if (typeof entry.id !== "string" || !entry.id) return;
	if (Array.isArray(entry.tasks) && !entry.tasks.includes("generate")) return;
	const modalities = entry.architecture?.input_modalities ?? entry.modalities?.input ?? known?.modalities?.input;
	const input = (Array.isArray(modalities) && modalities.includes("image")) ||
		(Array.isArray(entry.tasks) && entry.tasks.includes("vision"))
		? ["text", "image"] : ["text"];
	const contextWindow = positive(entry.context_length, entry.max_model_len, known?.limit?.context) ?? 8192;
	const maxTokens = positive(entry.max_output_tokens, known?.limit?.output) ?? Math.min(contextWindow, 8192);
	const efforts = Array.isArray(entry.reasoning_efforts) ? entry.reasoning_efforts
		: Array.isArray(known?.reasoning_options)
			? known.reasoning_options.find((option: Entry) => option?.type === "effort")?.values : undefined;
	const reasoning = typeof entry.reasoning === "boolean" ? entry.reasoning
		: known?.reasoning === true || (Array.isArray(efforts) && efforts.some((level) => level !== "none" && level !== "off"));
	const thinkingLevelMap: Partial<Record<Level, string | null>> = {};
	if (Array.isArray(efforts)) {
		for (const level of LEVELS) thinkingLevelMap[level] = efforts.includes(level) ? level : null;
		if (efforts.includes("none")) thinkingLevelMap.off = "none";
		// Privatemode supports none for its GLM models, even if the catalog omits it.
		if (profile === "privatemode-ai" && /^(glm-5\.3(-flash)?|glm(-flash)?-latest)$/.test(entry.id)) {
			thinkingLevelMap.off = "none";
		}
	}
	const cost = known?.cost ?? {};
	return {
		id: entry.id, name: known?.name ?? entry.id, reasoning, input,
		contextWindow, maxTokens: Math.min(maxTokens, contextWindow),
		cost: { input: cost.input ?? 0, output: cost.output ?? 0, cacheRead: cost.cache_read ?? 0, cacheWrite: cost.cache_write ?? 0 },
		...(Array.isArray(efforts) ? { thinkingLevelMap, compat: { thinkingFormat: "openai", supportsReasoningEffort: true } } : {}),
	};
}

export default async function (pi: ExtensionAPI) {
	const baseUrl = process.env.PI_OPENAI_BASE_URL?.replace(/\/+$/, "");
	if (!baseUrl) return;
	const apiKey = process.env.PI_OPENAI_API_KEY || "no-key";
	const profile = process.env.PI_OPENAI_PROFILE === "privatemode" ? "privatemode-ai" : process.env.PI_OPENAI_PROFILE ?? "";
	let knownModels: Record<string, Entry> = {};
	try {
		const catalog = JSON.parse(readFileSync(CATALOG_PATH, "utf8"));
		knownModels = catalog[profile]?.models ?? {};
		if (profile && !catalog[profile]) console.warn(`[${PROVIDER}] unknown catalog profile: ${profile}`);
	} catch (error) {
		console.warn(`[${PROVIDER}] cannot read model catalog: ${(error as Error).message}`);
	}
	let refreshPending: Promise<void> | undefined;
	function refresh(): Promise<void> {
		if (refreshPending) return refreshPending;
		refreshPending = (async () => {
			try {
				const response = await fetch(`${baseUrl}/models`, {
					headers: { Authorization: `Bearer ${apiKey}` }, signal: AbortSignal.timeout(3000),
				});
				if (!response.ok) throw new Error(`HTTP ${response.status}`);
				const payload: unknown = await response.json();
				if (!payload || typeof payload !== "object" || !Array.isArray((payload as Entry).data)) throw new Error("invalid model list");
				const models = (payload as Entry).data
					.filter((entry: unknown) => entry && typeof entry === "object")
					.map((entry: Entry) => modelFrom(entry, knownModels[entry.id], profile))
					.filter(Boolean);
				if (models.length === 0) throw new Error("no chat models found");
				const unknown = (payload as Entry).data.filter((entry: Entry) => entry && typeof entry === "object" &&
					typeof entry.id === "string" && (!Array.isArray(entry.tasks) || entry.tasks.includes("generate")) &&
					!positive(entry.context_length, entry.max_model_len, knownModels[entry.id]?.limit?.context));
				if (unknown.length) console.warn(`[${PROVIDER}] context unknown for: ${unknown.map((entry: Entry) => entry.id).join(", ")}; using 8192 tokens`);
				pi.registerProvider(PROVIDER, { baseUrl, apiKey, api: "openai-completions", models });
			} catch (error) {
				console.warn(`[${PROVIDER}] model discovery failed: ${(error as Error).message}`);
			}
		})().finally(() => { refreshPending = undefined; });
		return refreshPending;
	}
	await refresh();
	pi.on("input", async (event) => {
		if (event.text.trim().toLowerCase() === "/model") await refresh();
	});
}
