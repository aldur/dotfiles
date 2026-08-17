// Logging reverse proxy for OpenAI-compatible inference endpoints.
//
// Sits between a coding agent (pi, pi-rust) and llama-server and appends JSONL
// records carrying the verbatim request body, the response, and — for chat
// completions against a llama.cpp upstream — the prompt as the model actually
// receives it, rendered through the GGUF chat template.
//
// Two records per exchange, `state: "open"` when the request is forwarded and
// `state: "done"` when the response completes (or "error"/"aborted"). Logging
// only completed exchanges would blind the tool to exactly what it gets
// reached for: a request in flight against a slow model looks identical to a
// request that was never sent. An "open" with no matching "done" is the
// signature of a stall. Filter with `jq 'select(.state == "done")'`.
//
// The rendered prompt is the point. The request JSON only says which messages
// and tools were sent; the template decides how tool schemas are serialised
// into the system block and where the reasoning prefill lands, and that is
// what the model tokenizes.
//
// A `template` record snapshots the upstream's chat_template from /props —
// once per model, and again when it changes. Thus an archived transcript
// also carries the template source that made its prompts.

import { createServer, request as httpRequest } from "node:http";
import { chmodSync, appendFileSync, unlinkSync, statSync } from "node:fs";
import { brotliDecompressSync, gunzipSync, inflateSync } from "node:zlib";

const USAGE = `llama-wiretap — log what a coding agent sends to an inference server

Usage: llama-wiretap [options]

  --listen <target>    accept connections on <target>  (default 127.0.0.1:8080)
  --upstream <target>  forward to <target>             (default 127.0.0.1:8081)
  --log <file>         JSONL transcript                (default ./llama-wire.jsonl)
  --no-render          skip the /apply-template and /props lookups
  --no-redact          keep Authorization/API-key headers in the log
  --help

A <target> is host:port, or a path ending in .sock for a Unix domain socket —
the same rule llama-server's --host follows.

The proxy stands in front of the server, on the address the clients already
use. Move llama-server off that address, and no client needs a change:

  llama-server --port 8081 ...   # or: llama-server --host /tmp/llama.sock
  llama-wiretap                  # 127.0.0.1:8080 -> 127.0.0.1:8081
`;

// llama.cpp treats any --host ending in .sock as a Unix socket path; matching
// that convention keeps one spelling for both ends of the pipe.
function parseTarget(value, what) {
	if (value.endsWith(".sock")) {
		return { socketPath: value };
	}
	const match = /^(.*):(\d+)$/.exec(value);
	if (!match) {
		throw new Error(`${what}: expected host:port or a path ending in .sock, got "${value}"`);
	}
	// Strip the brackets IPv6 literals need in host:port form; node wants the
	// bare address.
	return { host: match[1].replace(/^\[(.*)\]$/, "$1"), port: Number(match[2]) };
}

function parseArgs(argv) {
	const opts = {
		listen: "127.0.0.1:8080",
		upstream: "127.0.0.1:8081",
		log: "llama-wire.jsonl",
		render: true,
		redact: true,
	};
	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];
		const next = () => {
			const value = argv[++i];
			if (value === undefined) throw new Error(`${arg} needs a value`);
			return value;
		};
		switch (arg) {
			case "--listen": opts.listen = next(); break;
			case "--upstream": opts.upstream = next(); break;
			case "--log": opts.log = next(); break;
			case "--no-render": opts.render = false; break;
			case "--no-redact": opts.redact = false; break;
			case "--help": case "-h": process.stdout.write(USAGE); process.exit(0); break;
			default: throw new Error(`unknown argument: ${arg}`);
		}
	}
	return opts;
}

const SECRET_HEADERS = new Set(["authorization", "x-api-key", "api-key", "proxy-authorization"]);

function headersForLog(headers, redact) {
	if (!redact) return headers;
	return Object.fromEntries(
		Object.entries(headers).map(([k, v]) => (SECRET_HEADERS.has(k.toLowerCase()) ? [k, "<redacted>"] : [k, v])),
	);
}

// Bodies are forwarded byte-for-byte; only the copy kept for the log is
// decompressed, so a compressed response still reads as text in the transcript.
function decodeBody(buffer, encoding) {
	try {
		if (encoding === "gzip") return gunzipSync(buffer);
		if (encoding === "deflate") return inflateSync(buffer);
		if (encoding === "br") return brotliDecompressSync(buffer);
	} catch {
		return buffer;
	}
	return buffer;
}

function asJsonOrText(buffer) {
	const text = buffer.toString("utf8");
	try {
		return { json: JSON.parse(text) };
	} catch {
		return { text };
	}
}

// POST the same messages/tools back to the upstream's /apply-template. Runs
// after the client's response is complete, so it never adds latency to the
// exchange being observed; a non-llama.cpp upstream just 404s and the record
// carries no prompt.
async function renderPrompt(upstream, payload) {
	const body = JSON.stringify({
		messages: payload.messages,
		...(payload.tools ? { tools: payload.tools } : {}),
		...(payload.chat_template_kwargs ? { chat_template_kwargs: payload.chat_template_kwargs } : {}),
	});
	const rendered = await once(upstream, "/apply-template", body);
	if (rendered.status !== 200) return undefined;
	const prompt = asJsonOrText(rendered.body).json?.prompt;
	if (typeof prompt !== "string") return undefined;

	// The token count is the cross-check: it must match the prompt_tokens the
	// upstream reports for the real call, otherwise the render drifted.
	const counted = await once(upstream, "/tokenize", JSON.stringify({ content: prompt, add_special: false }));
	const tokens = asJsonOrText(counted.body).json?.tokens;
	return { prompt, promptTokens: Array.isArray(tokens) ? tokens.length : undefined };
}

function once(upstream, path, body) {
	return new Promise((resolve, reject) => {
		const req = httpRequest(
			{ ...upstream, path, method: "POST", headers: { "content-type": "application/json", "content-length": Buffer.byteLength(body) } },
			(res) => {
				const chunks = [];
				res.on("data", (chunk) => chunks.push(chunk));
				res.on("end", () => resolve({ status: res.statusCode, body: Buffer.concat(chunks) }));
			},
		);
		req.on("error", reject);
		req.end(body);
	});
}

function get(upstream, path) {
	return new Promise((resolve, reject) => {
		const req = httpRequest({ ...upstream, path, method: "GET" }, (res) => {
			const chunks = [];
			res.on("data", (chunk) => chunks.push(chunk));
			res.on("end", () => resolve({ status: res.statusCode, body: Buffer.concat(chunks) }));
		});
		req.on("error", reject);
		req.end();
	});
}

// One record per template, not per exchange: a template is a few KB and only
// changes with a model swap or a server restart. The record goes in before
// the exchange's own "done" record. Thus a reader in file order knows which
// template each exchange used. The llama.cpp build is part of the snapshot:
// tokenizer fixes land in builds, so `--tokens` drift reports can name the
// build that made the capture.
const seenTemplates = new Map();
async function snapshotTemplate(upstream, model) {
	const path = model ? `/props?model=${encodeURIComponent(model)}&autoload=false` : "/props";
	const props = await get(upstream, path);
	if (props.status !== 200) return;
	const json = asJsonOrText(props.body).json;
	const template = json?.chat_template;
	if (typeof template !== "string") return;
	const buildInfo = typeof json.build_info === "string" ? json.build_info : undefined;
	const stamp = `${buildInfo ?? ""} ${template}`;
	if (seenTemplates.get(model ?? "") === stamp) return;
	seenTemplates.set(model ?? "", stamp);
	write({
		at: new Date().toISOString(),
		state: "template",
		model: model ?? null,
		...(buildInfo ? { buildInfo } : {}),
		chatTemplate: template,
	});
}

const opts = parseArgs(process.argv.slice(2));
const listen = parseTarget(opts.listen, "--listen");
const upstream = parseTarget(opts.upstream, "--upstream");
let exchangeId = 0;

const server = createServer((clientReq, clientRes) => {
	const id = ++exchangeId;
	const startedAt = new Date().toISOString();
	const reqChunks = [];
	clientReq.on("data", (chunk) => reqChunks.push(chunk));
	clientReq.on("end", () => {
		const reqBody = Buffer.concat(reqChunks);
		// The Host header names the proxy; the upstream is a different
		// authority, and for a Unix socket there is no authority at all.
		const headers = { ...clientReq.headers, host: upstream.socketPath ? "localhost" : `${upstream.host}:${upstream.port}` };

		const request = asJsonOrText(reqBody);
		write({
			id,
			at: startedAt,
			state: "open",
			method: clientReq.method,
			path: clientReq.url,
			requestHeaders: headersForLog(clientReq.headers, opts.redact),
			request: request.json ?? request.text,
		});

		const proxied = httpRequest(
			{ ...upstream, path: clientReq.url, method: clientReq.method, headers },
			(upstreamRes) => {
				clientRes.writeHead(upstreamRes.statusCode, upstreamRes.headers);
				const resChunks = [];
				upstreamRes.on("data", (chunk) => {
					resChunks.push(chunk);
					// Written through as it arrives: an SSE stream the agent
					// renders token by token must not be stalled by the tee.
					clientRes.write(chunk);
				});
				upstreamRes.on("end", () => {
					clientRes.end();
					void record(id, clientReq, reqBody, upstreamRes, Buffer.concat(resChunks));
				});
			},
		);
		proxied.on("error", (error) => {
			clientRes.writeHead(502, { "content-type": "application/json" });
			clientRes.end(JSON.stringify({ error: { message: `llama-wiretap: ${error.message}` } }));
			write({ id, at: startedAt, state: "error", path: clientReq.url, error: error.message });
		});
		clientReq.on("aborted", () => {
			proxied.destroy();
			// The client walked away mid-stream — a cancelled turn, or the agent
			// giving up on a model that is still generating.
			write({ id, at: startedAt, state: "aborted", path: clientReq.url });
		});
		proxied.end(reqBody);
	});
});

async function record(id, clientReq, reqBody, upstreamRes, resBody) {
	const request = asJsonOrText(reqBody);
	const entry = {
		id,
		// Its own timestamp, not the open one: the distance between the two
		// records is the latency of the exchange.
		at: new Date().toISOString(),
		state: "done",
		method: clientReq.method,
		path: clientReq.url,
		requestHeaders: headersForLog(clientReq.headers, opts.redact),
		request: request.json ?? request.text,
		status: upstreamRes.statusCode,
		responseHeaders: upstreamRes.headers,
		response: asJsonOrText(decodeBody(resBody, upstreamRes.headers["content-encoding"])).json
			?? decodeBody(resBody, upstreamRes.headers["content-encoding"]).toString("utf8"),
	};
	if (opts.render && request.json?.messages) {
		try {
			const rendered = await renderPrompt(upstream, request.json);
			if (rendered) Object.assign(entry, rendered);
		} catch (error) {
			entry.renderError = String(error);
		}
		try {
			await snapshotTemplate(upstream, request.json.model);
		} catch {
			// A non-llama.cpp upstream has no /props. The exchange record
			// stands on its own.
		}
	}
	write(entry);
}

function write(entry) {
	appendFileSync(opts.log, `${JSON.stringify(entry)}\n`);
}

if (listen.socketPath) {
	// A leftover socket from a killed run makes bind fail with EADDRINUSE;
	// only a socket is safe to clear, anything else is not ours to delete.
	try {
		if (statSync(listen.socketPath).isSocket()) unlinkSync(listen.socketPath);
	} catch {
		// Nothing there, which is the normal case.
	}
	server.listen(listen.socketPath, () => {
		// The transcript holds prompts and API keys; so does the socket that
		// feeds it. Owner-only, since bind() ignores the umask on some systems.
		chmodSync(listen.socketPath, 0o600);
		process.stderr.write(`llama-wiretap: ${listen.socketPath} -> ${opts.upstream}, logging to ${opts.log}\n`);
	});
	for (const signal of ["SIGINT", "SIGTERM"]) {
		process.on(signal, () => {
			try {
				unlinkSync(listen.socketPath);
			} catch {
				// Already gone.
			}
			process.exit(0);
		});
	}
} else {
	server.listen(listen.port, listen.host, () => {
		process.stderr.write(`llama-wiretap: ${opts.listen} -> ${opts.upstream}, logging to ${opts.log}\n`);
	});
}
