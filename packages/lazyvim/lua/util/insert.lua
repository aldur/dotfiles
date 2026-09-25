local M = {}

-- Capture the insert position before a picker moves focus or leaves insert mode.
-- Optional byte columns replace a range on the current line instead.
function M.capture(start_col, end_col)
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	local row, col = unpack(vim.api.nvim_win_get_cursor(win))
	col = start_col or col
	end_col = end_col or col
	return function(path)
		-- picker:close() queues the picker teardown on the event loop.
		-- This callback is queued after it, so the picker windows are
		-- gone when it runs and no later picker code stops insert mode.
		vim.schedule(function()
			if
				not (
					vim.api.nvim_win_is_valid(win)
					and vim.api.nvim_buf_is_valid(buf)
					and vim.api.nvim_win_get_buf(win) == buf
				)
			then
				return
			end
			-- Text, cursor and the queued `a` stay together, after the
			-- mode has settled. Setting the text before that opens an
			-- observable window where the line looks done while the
			-- prompt's insert mode still awaits its queued stopinsert —
			-- a key typed there executes as a normal-mode command once
			-- the stopinsert applies.
			local function resume()
				if
					not (
						vim.api.nvim_win_is_valid(win)
						and vim.api.nvim_buf_is_valid(buf)
						and vim.api.nvim_win_get_buf(win) == buf
					)
				then
					return
				end
				vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, end_col, { path })
				vim.api.nvim_set_current_win(win)
				-- The cursor goes on the path's last byte, where the
				-- queued `a` resumes typing at exactly col + #path,
				-- mid-line and at end of line alike. A queued key is
				-- safe where `startinsert` is not — the normal-mode
				-- loop processes it only after every pending mode
				-- change has been applied.
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
	end
end

return M
