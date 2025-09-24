return {
	-- This is required since otherwise lua-line, which depends on some
	-- `trouble.nvim` feature, will not initialise correctly.
	-- This is enabled with:
	-- vim.g.trouble_lualine = true
	{ "nvim-lualine/lualine.nvim", dependencies = { "folke/trouble.nvim" } },
	{
		"nvim-mini/mini.surround",
		opts = {
			mappings = {
				add = "gsa",
				delete = "gsd",
				find = "gsf",
				find_left = "gsF",
				highlight = "gsh",
				replace = "gsr",
				update_n_lines = "gsn",
			},
		},
	},
	{ "tpope/vim-fugitive", cmd = "G" },
	{
		"folke/todo-comments.nvim",
		opts = {
			highlight = {
				keyword = "bg", -- Highlight the keyword only.
			},
		},
	},
	{ -- https://github.com/LazyVim/LazyVim/issues/2491
		"okuuva/auto-save.nvim",
		opts = {},
		keys = { { "<leader>uv", "<cmd>ASToggle<CR>", desc = "Toggle autosave" } },
	},
	{
		"stevearc/conform.nvim",
		opts = {
			formatters_by_ft = {
				beancount = { "bean-format", lsp_format = "fallback" },
			},
			formatters = { ["bean-format"] = { prepend_args = { "-c", "70" } } },
		},
	},
}
