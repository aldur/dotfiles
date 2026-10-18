return {
	{
		"stevearc/conform.nvim",
		opts = function(_, opts)
			opts.formatters_by_ft = opts.formatters_by_ft or {}

			-- Only the audited markdownlint fixes may edit Markdown. Generic trimming
			-- removes hard line breaks, and other formatters can rewrite authored text.
			for _, ft in ipairs({ "markdown", "markdown.mdx" }) do
				opts.formatters_by_ft[ft] = nixCats("markdown") and { "markdownlint-cli2", lsp_format = "never" }
					or { lsp_format = "never" }
			end

			opts.formatters_by_ft["beancount"] = {
				"beans",
				"bean-format",
				stop_after_first = true,
				lsp_format = "fallback",
			}

			opts.formatters = opts.formatters or {}
			opts.formatters["bean-format"] = { prepend_args = { "-c", "70" } }
			opts.formatters["beans"] = {
				command = "beans",
				args = { "format", "--stdin" },
				stdin = true,
			}
		end,
	},
}
