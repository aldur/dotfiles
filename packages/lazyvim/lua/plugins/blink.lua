return {
	{
		"saghen/blink.cmp",
		opts = {
			sources = {
				providers = {
					snippets = {
						opts = {
							search_paths = {
								-- `nixCats` adds the current config directory first in the runtime path.
								vim.api.nvim_list_runtime_paths()[1] .. "/snippets",
							},
							extended_filetypes = { markdown = { "jekyll" } },
						},
					},
				},
			},
		},
	},
}
