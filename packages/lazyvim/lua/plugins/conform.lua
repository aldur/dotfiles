return {
	{
		"stevearc/conform.nvim",
		opts = function(_, opts)
			opts.formatters_by_ft = opts.formatters_by_ft or {}

			opts.formatters_by_ft["markdown"] = opts.formatters_by_ft["markdown"] or {}
			table.insert(opts.formatters_by_ft["markdown"], "trim_whitespace")

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
