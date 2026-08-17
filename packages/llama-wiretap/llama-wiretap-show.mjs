// Reads a llama-wiretap transcript and prints one exchange the way a person
// reads it: every message that was sent, the model's reasoning, and its answer.
//
// These live in different places — the messages in the request payload, the
// reasoning in the stream's `reasoning_content` deltas and the answer in its
// `content` deltas — so pulling them apart by hand means a jq expression long
// enough to get re-derived every time.
//
// `--rendered` is the one that answers "what did the model literally read":
// the request's messages are still pi's structured view, while the rendered
// prompt is the single string the chat template produced from them, tool
// schemas and control tokens included, and is what actually gets tokenized.

import { readFileSync } from "node:fs";

const USAGE = `llama-wiretap-show — read one exchange out of a llama-wiretap transcript

Usage: llama-wiretap-show [log] [options]

  log            transcript to read      (default ./llama-wire.jsonl)
  --id <n>       a specific exchange     (default: the last completed one)
  --list         one line per exchange
  --rendered     the literal templated string plus the reply, without the thread
  --full         everything: the thread, the literal string, thinking, answer
  --all          every exchange in the log, not just one
  --raw          the response stream as it arrived, unparsed
  --help
`;

const opts = { log: "llama-wire.jsonl", id: undefined, list: false, raw: false, rendered: false, full: false, all: false };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
	const arg = argv[i];
	if (arg === "--help" || arg === "-h") { process.stdout.write(USAGE); process.exit(0); }
	else if (arg === "--list") opts.list = true;
	else if (arg === "--raw") opts.raw = true;
	else if (arg === "--rendered") opts.rendered = true;
	else if (arg === "--full") opts.full = true;
	else if (arg === "--all") opts.all = true;
	else if (arg === "--id") opts.id = Number(argv[++i]);
	else if (arg.startsWith("--")) { process.stderr.write(`unknown argument: ${arg}\n`); process.exit(2); }
	else opts.log = arg;
}

let records;
try {
	records = readFileSync(opts.log, "utf8")
		.split("\n")
		.filter((line) => line.trim())
		.map((line) => JSON.parse(line));
} catch (error) {
	process.stderr.write(`llama-wiretap-show: cannot read ${opts.log}: ${error.message}\n`);
	process.exit(1);
}

// Escape codes only when a terminal is on the other end: this output gets
// piped into grep and redirected to files constantly, and literal \u001b[1m
// in a transcript is worse than no bold.
const tty = process.stdout.isTTY && !process.env.NO_COLOR;
const style = (code, text) => (tty ? `\u001b[${code}m${text}\u001b[0m` : text);
const bold = (text) => style("1", text);
const dim = (text) => style("2", text);
const cyan = (text) => style("36", text);

const section = (title, body) => `\n${bold(`── ${title} ──`)}\n${body || dim("(empty)")}\n`;
const out = (text) => process.stdout.write(text);

const isCompletion = (r) => typeof r.path === "string" && r.path.includes("/chat/completions");

// pi writes its own JSONL under ~/.pi/agent/sessions/<project>/. It is a
// different shape from a proxy transcript and carries less — no system prompt,
// no tool schemas, and no rendered string, because pi records what it decided
// rather than what it sent. What it does have is every turn with its thinking,
// for sessions captured long before any proxy existed.
const isSession = records.some((r) => r.type === "session" || r.type === "message");

function renderBlocks(content) {
	if (typeof content === "string") return { text: content, thinking: "", calls: [] };
	const out = { text: "", thinking: "", calls: [] };
	for (const block of Array.isArray(content) ? content : []) {
		if (block.type === "text") out.text += block.text ?? "";
		else if (block.type === "thinking") out.thinking += block.thinking ?? "";
		else if (block.type === "toolCall") out.calls.push(`→ ${block.name}(${JSON.stringify(block.arguments ?? {})})`);
		else if (block.type === "toolResult") out.text += (block.content ?? []).map((c) => c.text ?? "").join("");
	}
	return out;
}

function showSession() {
	const meta = records.find((r) => r.type === "session") ?? {};
	const model = records.find((r) => r.type === "model_change") ?? {};
	out(`session ${meta.id ?? "?"} — ${model.provider ?? "?"}/${model.modelId ?? "?"}, cwd ${meta.cwd ?? "?"}\n`);
	out(dim("(a pi session records turns only — no system prompt, tool schemas or rendered string; capture through llama-wiretap for those)\n"));

	let turn = 0;
	for (const entry of records.filter((r) => r.type === "message")) {
		const message = entry.message ?? {};
		turn += 1;
		const { text, thinking, calls } = renderBlocks(message.content);
		if (message.role === "toolResult") {
			out(section(`${turn}. TOOL RESULT (${message.toolName ?? "?"})`, text));
			continue;
		}
		if (message.role === "assistant") {
			if (thinking) out(section(`${turn}. THINKING`, thinking));
			out(section(`${turn}. ANSWER`, [text, ...calls].filter(Boolean).join("\n")));
			continue;
		}
		out(section(`${turn}. ${String(message.role ?? "?").toUpperCase()}`, [text, ...calls].filter(Boolean).join("\n")));
	}
}

// An exchange spans two records; the "open" one carries the request and is all
// there is while a slow model is still generating.
function duration(open, close) {
	if (!open?.at || !close?.at) return undefined;
	const ms = Date.parse(close.at) - Date.parse(open.at);
	return Number.isFinite(ms) ? ms : undefined;
}

const humanMs = (ms) => (ms === undefined ? "" : ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`);

function exchange(id) {
	const parts = records.filter((r) => r.id === id);
	return {
		id,
		open: parts.find((r) => r.state === "open"),
		done: parts.find((r) => r.state === "done"),
		failed: parts.find((r) => r.state === "error" || r.state === "aborted"),
	};
}

if (isSession) {
	showSession();
	process.exit(0);
}

const ids = [...new Set(records.filter(isCompletion).map((r) => r.id))];

if (opts.list) {
	for (const id of ids) {
		const e = exchange(id);
		const state = e.done ? `done ${e.done.status}` : (e.failed?.state ?? "in flight");
		const tokens = e.done?.promptTokens ? `${e.done.promptTokens} prompt tokens` : "";
		process.stdout.write(`${String(id).padStart(3)}  ${(e.open?.at ?? "").slice(11, 19)}  ${state.padEnd(12)} ${tokens}\n`);
	}
	process.exit(0);
}

const chosen = opts.all
	? ids.filter((i) => exchange(i).done || exchange(i).open)
	: [opts.id ?? [...ids].reverse().find((i) => exchange(i).done) ?? ids.at(-1)];

if (chosen[0] === undefined) {
	process.stderr.write(`llama-wiretap-show: no chat completions in ${opts.log}\n`);
	process.exit(1);
}

// Content blocks arrive either as a plain string or as typed parts.
function flatten(content) {
	if (typeof content === "string") return content;
	if (Array.isArray(content)) return content.map((part) => part.text ?? "").join("");
	return "";
}

// An agent turn is mostly tool traffic, and none of it lives in `content`: a
// call is a `tool_calls` entry on an assistant message and its result comes
// back as a `tool` message keyed by id. Rendering only `content` would show
// the bulk of a coding conversation as empty.
function renderMessage(message) {
	const parts = [];
	const text = flatten(message.content);
	if (text) parts.push(text);
	for (const call of message.tool_calls ?? []) {
		parts.push(`→ ${call.function?.name ?? "?"}(${call.function?.arguments ?? ""})`);
	}
	return parts.join("\n");
}

function label(message, index) {
	const role = String(message.role ?? "?").toUpperCase();
	// Numbered so a long thread can be read against the rendered prompt, where
	// the same turns appear inline with no separators.
	return message.role === "tool" ? `${index}. TOOL RESULT (${message.tool_call_id ?? "?"})` : `${index}. ${role}`;
}

function deltas(response, field) {
	if (typeof response !== "string") return "";
	return response
		.split("\n")
		.filter((line) => line.startsWith("data: {"))
		.map((line) => {
			try {
				return JSON.parse(line.slice(6)).choices?.[0]?.delta?.[field] ?? "";
			} catch {
				return "";
			}
		})
		.join("");
}


function show(id) {
	const { open, done, failed } = exchange(id);
	const record = done ?? open;
	if (!record) {
		process.stderr.write(`llama-wiretap-show: no exchange with id ${id}\n`);
		process.exit(1);
	}

	const status = done ? `${done.status}` : (failed?.state ?? "still in flight");
	const tokens = done?.promptTokens ? `, ${done.promptTokens} prompt tokens` : "";
	out(`${opts.all ? "\n" : ""}exchange ${id} — ${status}${tokens}, ${record.at}\n`);

	if (opts.raw) {
		out(section("RESPONSE STREAM", typeof done?.response === "string" ? done.response : JSON.stringify(done?.response, null, 2)));
		return;
	}

	// The rendered string already contains the whole thread inline, so showing
	// the structured messages beside it is duplication unless asked for.
	const wantsThread = !opts.rendered || opts.full;
	const wantsRendered = opts.rendered || opts.full;

	if (wantsThread) {
		const tools = record.request?.tools ?? [];
		if (tools.length) {
			out(section("TOOLS", tools.map((tool) => `- ${tool.function?.name}: ${tool.function?.description ?? ""}`.trim()).join("\n")));
		}
		(record.request?.messages ?? []).forEach((message, index) => {
			out(section(label(message, index + 1), renderMessage(message)));
		});
	}

	if (wantsRendered) {
		// Only the proxy's render carries the literal string, and only when the
		// upstream speaks llama.cpp; nothing else can reconstruct it.
		if (typeof done?.prompt === "string") {
			out(section("RENDERED PROMPT (what the model tokenized)", done.prompt));
		} else if (opts.rendered && !opts.full && !opts.all) {
			process.stderr.write(
				"llama-wiretap-show: no rendered prompt on this exchange — it needs a completed\n" +
				"llama.cpp exchange captured without --no-render.\n",
			);
			process.exit(1);
		}
	} else if (done?.prompt) {
		out("(--rendered for the literal templated string the model tokenized)\n");
	}

	if (done) {
		out(section("THINKING", deltas(done.response, "reasoning_content")));
		out(section("ANSWER", deltas(done.response, "content")));
	} else {
		// Nothing came back yet. Say so rather than printing two empty sections
		// that read like the model answered with silence.
		out("\nNo response yet — the model is still generating, or the request died.\n");
	}
}

for (const id of chosen) show(id);
