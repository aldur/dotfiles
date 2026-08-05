vim.api.nvim_create_user_command("Terminal", function(_)
	---@diagnostic disable-next-line: undefined-global
	Snacks.terminal.open(nil, { win = { position = "right" } })
end, {})
