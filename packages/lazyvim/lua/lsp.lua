local servers = {
	{ "beancount", "beancount-language-server" },
	{ "clarinet", "clarinet" },
	{ "forge_lsp", "forge" },
	{ "solidity_ls", "vscode-solidity-server" },
	{ "solidity_ls_nomicfoundation", "nomicfoundation-solidity-language-server" },
}

local enabled = {}
for _, server in ipairs(servers) do
	if vim.fn.executable(server[2]) == 1 then
		table.insert(enabled, server[1])
	end
end

vim.lsp.enable(enabled)
