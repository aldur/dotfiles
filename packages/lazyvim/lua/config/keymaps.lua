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

-- Project-wide fuzzy file completion on the native completion chord: the
-- picked path is typed into the buffer where insert mode left off. Exercised
-- end to end by checks/lazyvim-insert-path.lua.
vim.keymap.set("i", "<C-x><C-f>", function()
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	-- In insert mode the cursor column is the byte the next typed character
	-- would land on; leaving insert mode (which opening the picker does)
	-- shifts the cursor left, so the spot has to be taken now.
	local row, col = unpack(vim.api.nvim_win_get_cursor(win))
	Snacks.picker.files({
		confirm = function(picker, item)
			picker:close()
			if not (item and vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)) then
				return
			end
			local path = item.file
			-- picker:close() queues the picker teardown on the event loop.
			-- This callback is queued after it, so the picker windows are
			-- gone when it runs and no later picker code stops insert mode.
			vim.schedule(function()
				if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)) then
					return
				end
				vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { path })
				vim.api.nvim_set_current_win(win)
				local function resume()
					if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)) then
						return
					end
					-- Leaving insert mode shifts the cursor left, so the
					-- cursor is placed only now: on the path's last byte,
					-- where the queued `a` resumes typing at exactly
					-- col + #path, mid-line and at end of line alike. A
					-- queued key is safe where `startinsert` is not — the
					-- normal-mode loop processes it only after every
					-- pending mode change has been applied.
					vim.api.nvim_win_set_cursor(win, { row, col + #path - 1 })
					vim.api.nvim_feedkeys("a", "n", false)
				end
				-- The prompt's stopinsert (issued inside picker:close) only
				-- applies once the editor unwinds, and this callback can run
				-- before that. ModeChanged marks the moment insert mode has
				-- actually ended; the extra stopinsert backstops the
				-- picker's, so the event always arrives.
				if vim.api.nvim_get_mode().mode:find("^i") then
					vim.cmd.stopinsert()
					vim.api.nvim_create_autocmd("ModeChanged", {
						pattern = "i*:*",
						once = true,
						callback = resume,
					})
				else
					resume()
				end
			end)
		end,
	})
end, { desc = "Insert file path (fuzzy)" })
