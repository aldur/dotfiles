// A stand-in for llama-server, for ./test.nix. Implements just the three
// routes the proxy touches, with the same shapes llama.cpp uses: a streaming
// chat completion, /apply-template, and /tokenize.
//
// The prompt it renders embeds the tool names and message contents it was
// given, so the test can prove the proxy forwarded the real payload rather
// than a reconstruction, and prompt_tokens agrees with /tokenize so the
// proxy's cross-check has something to agree with.

import { createServer } from "node:http";

const target = process.argv[2];

function render(payload) {
	const tools = (payload.tools ?? []).map((t) => t.function.name).join(" ");
	const messages = (payload.messages ?? []).map((m) => `${m.role} ${m.content}`).join(" ");
	return `<|im_start|>system TOOLS ${tools} ${messages} <|im_start|>assistant`;
}

const tokenize = (prompt) => prompt.split(/\s+/).filter(Boolean);

createServer((req, res) => {
	const chunks = [];
	req.on("data", (chunk) => chunks.push(chunk));
	req.on("end", () => {
		const body = Buffer.concat(chunks).toString("utf8");
		const payload = body ? JSON.parse(body) : {};

		if (req.url.startsWith("/props")) {
			// The template names the model, so the test can see that the proxy
			// asked for the right one and dedups per model.
			const model = new URL(req.url, "http://upstream").searchParams.get("model") ?? "default";
			res.writeHead(200, { "content-type": "application/json" });
			res.end(JSON.stringify({ chat_template: `TEMPLATEMARK-${model} {{ messages }}` }));
			return;
		}
		if (req.url === "/apply-template") {
			res.writeHead(200, { "content-type": "application/json" });
			res.end(JSON.stringify({ prompt: render(payload) }));
			return;
		}
		if (req.url === "/tokenize") {
			res.writeHead(200, { "content-type": "application/json" });
			res.end(JSON.stringify({ tokens: tokenize(payload.content).map((_, i) => i + 1) }));
			return;
		}
		if (req.url === "/v1/chat/completions") {
			const promptTokens = tokenize(render(payload)).length;
			if (payload.stream) {
				res.writeHead(200, { "content-type": "text/event-stream" });
				// Reasoning arrives on its own delta field, ahead of the answer —
				// the split llama-wiretap-show has to reproduce.
				res.write(`data: ${JSON.stringify({ choices: [{ delta: { reasoning_content: "thinking out loud" } }] })}\n\n`);
				for (const word of ["he", "llo"]) {
					res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: word } }] })}\n\n`);
				}
				res.write(`data: ${JSON.stringify({ usage: { prompt_tokens: promptTokens } })}\n\n`);
				res.end("data: [DONE]\n\n");
				return;
			}
			res.writeHead(200, { "content-type": "application/json" });
			res.end(
				JSON.stringify({
					choices: [{ message: { role: "assistant", content: "hello" } }],
					usage: { prompt_tokens: promptTokens },
				}),
			);
			return;
		}
		res.writeHead(404, { "content-type": "application/json" });
		res.end(JSON.stringify({ error: "not found" }));
	});
}).listen(
	target.endsWith(".sock") ? target : Number(target.split(":")[1]),
	target.endsWith(".sock") ? undefined : target.split(":")[0],
	() => process.stderr.write(`test-upstream: listening on ${target}\n`),
);
