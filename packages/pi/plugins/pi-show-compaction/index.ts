/**
 * Show the compaction result in the chat.
 *
 * pi renders a compaction as one collapsed line: "Compacted from N tokens
 * (ctrl+o to expand)". This extension appends a custom entry with the full
 * summary after each compaction. The renderer always shows the summary as
 * expanded Markdown. Custom entries do not go to the LLM, so the summary
 * is not sent twice.
 */

import { type ExtensionAPI, getMarkdownTheme } from "@earendil-works/pi-coding-agent";
import { Box, Markdown, Spacer, Text } from "@earendil-works/pi-tui";

const ENTRY_TYPE = "pi-show-compaction";

interface CompactionData {
	summary: string;
	tokensBefore: number;
	/** What caused the compaction: "manual", "threshold", or "overflow". */
	reason: string;
}

export default function (pi: ExtensionAPI) {
	pi.registerEntryRenderer<CompactionData>(ENTRY_TYPE, (entry, _options, theme) => {
		const data = entry.data;
		if (!data?.summary) return undefined;

		// The same look as pi's own compaction line: a customMessageBg box
		// with a bold label.
		const box = new Box(1, 1, (text) => theme.bg("customMessageBg", text));
		const label =
			theme.fg("customMessageLabel", "\x1b[1m[compaction summary]\x1b[22m") +
			theme.fg("dim", ` ${data.reason}, from ${data.tokensBefore.toLocaleString()} tokens`);
		box.addChild(new Text(label, 0, 0));
		box.addChild(new Spacer(1));
		box.addChild(
			new Markdown(data.summary, 0, 0, getMarkdownTheme(), {
				color: (text) => theme.fg("customMessageText", text),
			}),
		);
		return box;
	});

	pi.on("session_compact", async (event) => {
		pi.appendEntry<CompactionData>(ENTRY_TYPE, {
			summary: event.compactionEntry.summary,
			tokensBefore: event.compactionEntry.tokensBefore,
			reason: event.reason,
		});
	});
}
