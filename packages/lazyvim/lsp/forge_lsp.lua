-- The Solar language server that forge >= 1.8.0 embeds.
-- An old forge has no `lsp` subcommand and exits at start.
--
-- `nvim-lint` is still required to expose lint notes.
---@type vim.lsp.Config
return {
	cmd = { "forge", "lsp" },
	filetypes = { "solidity" },
	-- Attach only inside a foundry project. Outside one, the server
	-- has no `foundry.toml` to read its configuration from.
	root_dir = function(bufnr, on_dir)
		local root = vim.fs.root(bufnr, "foundry.toml")
		if root then
			on_dir(root)
		end
	end,
}
