return {
	{
		"qadzek/link.vim",
		ft = { "markdown", "gitcommit" },
		init = function()
			vim.g.link_heading = ""
			vim.g.link_disable_internal_links = 1
		end,
	},
}
