-- Keymaps loaded after LazyVim's defaults (on the `VeryLazy` event).

-- When launched from the tmux popup (prefix + e), `q` in normal mode quits
-- Neovim, which closes the `-E` popup — mirroring lazygit's `q`. Scoped to the
-- popup via NVIM_POPUP so normal nvim keeps `q` for macro recording.
-- Buffer-local `q` (help, quickfix, pickers, dashboard, …) still wins, so those
-- close their own window first.
if vim.env.NVIM_POPUP == "1" then
	vim.keymap.set("n", "q", "<cmd>qa<cr>", { desc = "Quit (close tmux popup)", silent = true })
end
