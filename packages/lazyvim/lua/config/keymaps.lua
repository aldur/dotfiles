-- Keymaps loaded after LazyVim's defaults (on the `VeryLazy` event).

-- When launched from a tmux popup, nvim runs inside a detached,
-- per-window tmux session, so the popup is persistent:
if vim.env.NVIM_POPUP == "1" then
	vim.keymap.set("n", "q", function()
		-- Detach the client(s) on THIS popup's own session. Resolve the session
		-- live (#S) so it's always right, and target it with -s so we can only
		-- ever detach the popup — never the outer terminal. (A bare
		-- `detach-client` picks the "current client", which inside a nested
		-- popup is the parent terminal, dropping you out of tmux entirely.)
		local session = vim.fn.systemlist({ "tmux", "display-message", "-p", "#S" })[1]
		if session and session ~= "" then
			vim.fn.system({ "tmux", "detach-client", "-s", session })
		end
	end, { desc = "Background (hide tmux popup)", silent = true })
end
