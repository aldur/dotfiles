vim.api.nvim_create_user_command("Terminal", function(_)
	Snacks.terminal.open(nil, { win = { position = "right" } })
end, {})
