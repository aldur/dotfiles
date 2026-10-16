/**
 * Throughput for any Pi provider. Prefer server timings (llama.cpp, Sushi,
 * mlx-serve, vLLM); otherwise label client estimates with ~. Input / TTFT is
 * a separate estimate, since queueing, caching and transport affect it.
 * Live estimates use characters / 4 over recent output, including thinking
 * and tool arguments, and refresh through pauses. Final usage gives the reply
 * average. No fetch wrapper or server polling is needed.
 * The existing pi-statusline renders this extension's status.
 *
 * Protocol: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
 * Related extension: https://github.com/eliaskg/pi-prefill
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "pi-throughput";
// The bundled Hugging Face provider and Pi's built-in llama.cpp provider.
const PROGRESS_PROVIDERS = new Set(["llama-cpp", "llama.cpp"]);
const DECODE_WINDOW_MS = 2000;
const REFRESH_MS = 250;

function record(value: unknown): Record<string, unknown> | undefined {
	return value !== null && typeof value === "object" && !Array.isArray(value)
		? (value as Record<string, unknown>)
		: undefined;
}

function nonnegative(value: unknown): value is number {
	return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function rate(timings: Record<string, unknown>, phase: "prompt" | "predicted"): number | undefined {
	const reported = timings[`${phase}_per_second`];
	if (nonnegative(reported) && reported > 0) return reported;
	let tokens = timings[`${phase}_n`];
	// Sushi / mlx-serve's prompt_n includes cached_n; llama.cpp's prompt_n
	// already excludes cache_n. Respect the two wire formats.
	if (phase === "prompt" && nonnegative(tokens) && nonnegative(timings.cached_n)) {
		tokens = Math.max(0, tokens - timings.cached_n);
	}
	const ms = timings[`${phase}_ms`];
	const computed = nonnegative(tokens) && nonnegative(ms) && ms > 0 ? (tokens / ms) * 1000 : undefined;
	return nonnegative(computed) ? computed : undefined;
}

export default function (pi: ExtensionAPI) {
	let request: {
		provider: string; model: string; api: string; started: number;
		firstOutput?: number; lastOutput?: number; characters: number;
		samples: { at: number; characters: number }[];
	} | undefined;
	let prefill: number | "cached" | undefined;
	let inputRate: number | undefined;
	let decode: number | undefined;
	let serverDecode = false;
	let percent: number | undefined;
	let lastStatus: string | undefined;
	let lastRender = 0;
	let refreshTimer: ReturnType<typeof setInterval> | undefined;

	function stopRefreshing() {
		clearInterval(refreshTimer);
		refreshTimer = undefined;
	}

	function updateDecode(now: number) {
		if (!request || serverDecode || request.firstOutput === undefined) return;
		const samples = request.samples;
		// Keep the sample just before the window as its baseline. This also
		// lets the estimate fall to zero when output stops arriving.
		while (samples.length > 1 && samples[1].at <= now - DECODE_WINDOW_MS) samples.shift();
		const first = samples[0];
		const seconds = (now - first.at) / 1000;
		if (seconds > 0) decode = ((request.characters - first.characters) / 4) / seconds;
	}

	function startRefreshing(ctx: ExtensionContext) {
		if (refreshTimer) return;
		refreshTimer = setInterval(() => {
			if (!request || ctx.signal?.aborted) { stopRefreshing(); return; }
			updateDecode(performance.now());
			render(ctx);
		}, REFRESH_MS);
		refreshTimer.unref();
	}

	function clear(ctx: ExtensionContext) {
		stopRefreshing();
		request = undefined;
		prefill = inputRate = decode = percent = undefined;
		serverDecode = false;
		lastStatus = undefined;
		lastRender = 0;
		if (ctx.mode === "tui") ctx.ui.setStatus(STATUS_KEY, undefined);
	}

	function render(ctx: ExtensionContext, force = false) {
		const now = performance.now();
		if (!force && lastStatus !== undefined && now - lastRender < 100) return;
		const parts: string[] = [];
		if (prefill !== undefined || percent !== undefined) {
			let text = prefill === "cached" ? "cached" : prefill === undefined ? "…" : `${prefill.toFixed(1)} tok/s`;
			if (percent !== undefined) text += ` ${percent}%`;
			parts.push(`prefill:${text}`);
		}
		else if (inputRate !== undefined) parts.push(`input/TTFT:~${inputRate.toFixed(1)} tok/s`);
		if (decode !== undefined) parts.push(`decode:${serverDecode ? "" : "~"}${decode.toFixed(1)} tok/s`);
		else if (refreshTimer && request?.firstOutput !== undefined) parts.push("decode:…");
		if (request?.firstOutput !== undefined) {
			parts.push(`TTFT:${((request.firstOutput - request.started) / 1000).toFixed(2)}s`);
		}
		const status = parts.length ? ctx.ui.theme.fg("dim", parts.join(" | ")) : undefined;
		if (status !== lastStatus) {
			lastStatus = status;
			lastRender = now;
			ctx.ui.setStatus(STATUS_KEY, status);
		}
	}

	pi.on("before_provider_request", (event, ctx) => {
		if (ctx.mode !== "tui" || ctx.isIdle()) return;
		const model = ctx.model;
		if (!model) return;
		const payload = record(event.payload);
		if (!payload || payload.stream === false) return;
		// Pi's Gemini payload has no model field. Skip a routed request when
		// another model is named explicitly.
		if (typeof payload.model === "string" && payload.model !== model.id) return;
		clear(ctx);
		request = {
			provider: model.provider, model: model.id, api: model.api,
			started: performance.now(), characters: 0, samples: [],
		};
		// Only llama.cpp needs these nonstandard request fields. Other servers
		// are observed without changing their requests.
		if (model.api === "openai-completions" && PROGRESS_PROVIDERS.has(model.provider)) {
			return { ...payload, return_progress: true, timings_per_token: true };
		}
	});

	pi.on("provider_stream_event", (event, ctx) => {
		if (
			ctx.mode !== "tui" || ctx.signal?.aborted || !request ||
			event.api !== request.api || event.provider !== request.provider || event.model !== request.model
		) return;
		const chunk = record(event.data);
		if (!chunk) return;
		const progress = record(chunk.prompt_progress);
		if (progress) {
			const { total, cache, processed, time_ms: ms } = progress;
			if (
				nonnegative(total) && nonnegative(cache) && nonnegative(processed) && nonnegative(ms) &&
				cache <= processed && processed <= total
			) {
				const work = total - cache;
				percent = work > 0 ? Math.round(((processed - cache) * 100) / work) : 100;
				prefill = work === 0 ? "cached" : ms > 0 ? ((processed - cache) * 1000) / ms : undefined;
			}
		}
		const timings = record(chunk.timings) ?? record(record(chunk.response)?.timings);
		if (timings) {
			const promptRate = rate(timings, "prompt");
			if (timings.prompt_n === 0 || (
				nonnegative(timings.prompt_n) && nonnegative(timings.cached_n) && timings.prompt_n === timings.cached_n
			)) prefill = "cached";
			else if (promptRate !== undefined) prefill = promptRate;
			const decodeRate = rate(timings, "predicted");
			if (decodeRate !== undefined && decodeRate > 0) {
				decode = decodeRate;
				serverDecode = true;
			}
			// Once generation starts, retain prefill speed without the progress percentage.
			if (nonnegative(timings.predicted_n) && timings.predicted_n > 0) percent = undefined;
		}
		// Recent vLLM versions emit this with --enable-per-request-metrics.
		const metrics = record(chunk.metrics);
		const completionTokens = record(chunk.usage)?.completion_tokens;
		// vLLM's tokens_per_second includes prefill. Pure decode spans the
		// intervals from the first generated token to the last instead.
		if (
			nonnegative(metrics?.generation_time_ms) && metrics.generation_time_ms > 0 &&
			nonnegative(completionTokens) && completionTokens > 1
		) {
			decode = ((completionTokens - 1) / metrics.generation_time_ms) * 1000;
			serverDecode = true;
		}
		render(ctx, record(chunk.usage) !== undefined);
	});

	pi.on("message_update", (event, ctx) => {
		if (ctx.mode !== "tui" || ctx.signal?.aborted || !request) return;
		const message = event.message;
		if (message.role !== "assistant" || message.provider !== request.provider || message.model !== request.model) return;
		const delta = event.assistantMessageEvent;
		if (delta.type !== "text_delta" && delta.type !== "thinking_delta" && delta.type !== "toolcall_delta") return;
		if (!delta.delta) return;
		const now = performance.now();
		request.characters += delta.delta.length;
		if (request.firstOutput === undefined) {
			request.firstOutput = now;
			startRefreshing(ctx);
		}
		request.lastOutput = now;
		if (!serverDecode) request.samples.push({ at: now, characters: request.characters });
		percent = undefined;
		// Some providers report prompt usage before generation finishes.
		const input = (message.usage?.input ?? 0) + (message.usage?.cacheWrite ?? 0);
		const ttft = (request.firstOutput - request.started) / 1000;
		if (prefill === undefined && input > 0 && ttft > 0) inputRate = input / ttft;
		// These are estimates: providers can buffer or bundle multiple tokens
		// per delta. Do not let them replace a server-reported decode rate.
		updateDecode(now);
		render(ctx);
	});

	pi.on("message_end", (event, ctx) => {
		const message = event.message;
		if (message.role !== "assistant") return;
		if (message.stopReason === "error" || message.stopReason === "aborted") { clear(ctx); return; }
		if (ctx.mode !== "tui" || !request || message.provider !== request.provider || message.model !== request.model) return;
		stopRefreshing();
		if (request.firstOutput !== undefined) {
			const ttft = (request.firstOutput - request.started) / 1000;
			const input = message.usage.input + message.usage.cacheWrite;
			if (prefill === undefined && ttft > 0 && input > 0) inputRate = input / ttft;
			const seconds = ((request.lastOutput ?? request.firstOutput) - request.firstOutput) / 1000;
			if (!serverDecode && seconds > 0 && message.usage.output > 1) decode = (message.usage.output - 1) / seconds;
		}
		percent = undefined;
		render(ctx, true);
		request = undefined;
	});
	pi.on("agent_end", () => { stopRefreshing(); request = undefined; });
	pi.on("session_start", (_event, ctx) => clear(ctx));
	pi.on("session_tree", (_event, ctx) => clear(ctx));
	pi.on("model_select", (_event, ctx) => clear(ctx));
	pi.on("session_shutdown", (_event, ctx) => clear(ctx));
}
