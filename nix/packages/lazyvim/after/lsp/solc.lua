local util = require("lspconfig.util")

---@type vim.lsp.Config
return {
	cmd = { "solc-remappings-lsp" },
	root_dir = function(bufnr, on_dir)
		local fname = vim.api.nvim_buf_get_name(bufnr)
		on_dir(util.root_pattern("foundry.toml", "hardhat.config.*", ".git")(fname))
	end,
}
