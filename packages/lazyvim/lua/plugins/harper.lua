return {
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				harper_ls = {
					filetypes = { "gitcommit", "markdown" },
					settings = {
						["harper-ls"] = {
							linters = {
								SentenceCapitalization = false,
								SpellCheck = false,
							},
						},
					},
				},
			},
		},
	},
}
