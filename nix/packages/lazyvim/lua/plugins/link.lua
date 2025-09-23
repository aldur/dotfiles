return {
	{
		"qadzek/link.vim",
		init = function()
			vim.g.link_enabled_filetypes = { "markdown", "gitcommit" }
			vim.g.link_heading = ""
			vim.g.link_disable_internal_links = 1
		end,
	},
}
