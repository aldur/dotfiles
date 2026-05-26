return {
	-- Ensure blink.cmp loads before nvim-lspconfig so its `plugin/blink-cmp.lua`
	-- registers `textDocument.*` capabilities via `vim.lsp.config('*', ...)` before
	-- servers attach. Without this, gopls attaches with only LazyVim's default
	-- `workspace.fileOperations` caps and `extras/lang/go.lua:60` crashes reading
	-- `client.config.capabilities.textDocument.semanticTokens`.
	{ "neovim/nvim-lspconfig", dependencies = { "saghen/blink.cmp" } },
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
