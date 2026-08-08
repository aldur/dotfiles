/**
 * Claude Code's statusline, for pi.
 *
 * Mirrors the claude-statusline script (packages/claude-statusline), plus the
 * thinking level, which Claude Code has no statusline field for:
 *
 *   aldur/dotfiles master dotfiles | ░░░░░░░░░░ 5% cache:98% think:high [Opus 4.5 200k]
 *
 * Replaces pi's two-line footer (pwd/branch, then token totals and model) with
 * that single line. Extension statuses from setStatus() keep their own line, as
 * in the built-in footer, so plan-mode and friends still show up.
 */

import { execFileSync } from "node:child_process";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ThemeColor } from "@earendil-works/pi-coding-agent";
import { type TUI, truncateToWidth } from "@earendil-works/pi-tui";

const BAR_WIDTH = 10;

/** Last two path segments, like the awk in claude-statusline. */
function shortenDir(dir: string): string {
	const parts = dir.split("/");
	return parts.length > 2 ? `${parts[parts.length - 2]}/${parts[parts.length - 1]}` : dir;
}

/** basename of origin's URL, sans .git. Empty when there is no remote. */
function repoName(cwd: string): string {
	try {
		const remote = execFileSync("git", ["remote", "get-url", "origin"], {
			cwd,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "ignore"],
		}).trim();
		if (!remote) return "";
		return remote.replace(/\.git$/, "").split("/").pop() ?? "";
	} catch {
		return "";
	}
}

/** Cache hit rate of the most recent assistant response, as claude reports it. */
function latestCacheHitRate(messages: AssistantMessage[]): number | undefined {
	const last = messages[messages.length - 1];
	if (!last) return undefined;
	const total = last.usage.input + last.usage.cacheRead + last.usage.cacheWrite;
	return total > 0 ? Math.floor((last.usage.cacheRead * 100) / total) : undefined;
}

/**
 * Claude reports "Opus 4.5"; pi's catalog says "Claude Opus 4.5 (latest)".
 * Trim to the short form, and fall back to the id for models without a name
 * (local llama servers, custom providers).
 */
function displayModel(name: string | undefined, id: string): string {
	const short = (name ?? "").replace(/^Claude /, "").replace(/ \(latest\)$/, "");
	return short || id;
}

function barColor(percent: number): ThemeColor {
	if (percent >= 90) return "error";
	if (percent >= 70) return "warning";
	return "success";
}

export default function (pi: ExtensionAPI) {
	// One git call per cwd: the remote never changes mid-session, and render()
	// runs on every keystroke.
	const repoNames = new Map<string, string>();

	// pi repaints the footer on a thinking level change but does not request a
	// render for it (interactive-mode.ts, "thinking_level_changed"), so the line
	// would sit stale until the next keypress.
	let tui: TUI | undefined;
	pi.on("thinking_level_select", async () => {
		tui?.requestRender();
	});

	pi.on("session_start", async (_event, ctx) => {
		if (ctx.mode !== "tui") return;

		ctx.ui.setFooter((footerTui, theme, footerData) => {
			tui = footerTui;
			return {
				dispose: footerData.onBranchChange(() => footerTui.requestRender()),
				invalidate() {},
				render(width: number): string[] {
					const cwd = ctx.sessionManager.getCwd();
					let repo = repoNames.get(cwd);
					if (repo === undefined) {
						repo = repoName(cwd);
						repoNames.set(cwd, repo);
					}

					const usage = ctx.getContextUsage();
					const contextWindow = usage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
					// null right after compaction, until the next response reports usage.
					const percent = usage?.percent ?? null;
					const filled = percent === null ? 0 : Math.floor((percent * BAR_WIDTH) / 100);
					const bar = "█".repeat(filled) + "░".repeat(BAR_WIDTH - filled);

					const assistants: AssistantMessage[] = [];
					for (const entry of ctx.sessionManager.getBranch()) {
						if (entry.type === "message" && entry.message.role === "assistant") {
							assistants.push(entry.message as AssistantMessage);
						}
					}
					const cacheHit = latestCacheHitRate(assistants);

					const branch = footerData.getGitBranch();
					const model = ctx.model ? displayModel(ctx.model.name, ctx.model.id) : "no-model";

					let line = shortenDir(cwd);
					if (branch) line += ` ${theme.fg("success", branch)}`;
					if (repo) line += ` ${theme.fg("accent", repo)}`;
					line += ` | ${theme.fg(barColor(percent ?? 0), bar)}`;
					line += ` ${percent === null ? "?" : Math.floor(percent)}%`;
					if (cacheHit !== undefined) {
						line += ` ${theme.fg("dim", "cache:")}${theme.fg("success", `${cacheHit}%`)}`;
					}
					// Only reasoning models have a level to show, as in pi's own footer.
					if (ctx.model?.reasoning) {
						line += ` ${theme.fg("dim", "think:")}${pi.getThinkingLevel()}`;
					}
					line += ` ${theme.fg("accent", `[${model} ${Math.round(contextWindow / 1000)}k]`)}`;

					const lines = [truncateToWidth(line, width, theme.fg("dim", "..."))];

					const statuses = footerData.getExtensionStatuses();
					if (statuses.size > 0) {
						const status = Array.from(statuses.entries())
							.sort(([a], [b]) => a.localeCompare(b))
							.map(([, text]) => text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim())
							.join(" ");
						lines.push(truncateToWidth(status, width, theme.fg("dim", "...")));
					}
					return lines;
				},
			};
		});
	});
}
