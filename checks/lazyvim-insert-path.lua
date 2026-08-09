-- In-editor assertions for the insert-mode fuzzy path completion keymap
-- (packages/lazyvim/lua/config/keymaps.lua), driven by
-- checks/lazyvim-variants.nix.
--
-- Unlike lazyvim-probe.lua this runs *evented*, in nvim's main loop: the
-- chord has to travel through real input processing to fire the insert-mode
-- mapping, and the queued key that resumes typing is only processed once the
-- editor is back in its loop — a synchronous vim.wait() script can drive
-- neither. Each step polls for its condition and schedules the next; the
-- last one prints INSERT-PATH-OK and quits.

local dir = vim.env.PROBE_DIR

local failures = {}
local function check(name, ok, detail)
	if not ok then
		table.insert(failures, ("FAIL %s%s"):format(name, detail and (" — " .. tostring(detail)) or ""))
	end
end

local function finish()
	io.write(#failures == 0 and "INSERT-PATH-OK\n" or (table.concat(failures, "\n") .. "\n"))
	io.flush()
	vim.cmd("qa!")
end

local function line()
	return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
end

-- A step that never comes true fails its check with the editor's state at
-- that moment, rather than hanging the build until nix times it out.
local function poll(name, cond, next_step, timeout_ms)
	local waited = 0
	local function tick()
		local ok, res = pcall(cond)
		if ok and res then
			local oknext, err = pcall(next_step)
			if not oknext then
				check("step after '" .. name .. "'", false, err)
				finish()
			end
			return
		end
		waited = waited + 50
		if waited >= (timeout_ms or 20000) then
			local state = (" — line=[%s] mode=%s cursor=%s"):format(
				line(),
				vim.api.nvim_get_mode().mode,
				vim.inspect(vim.api.nvim_win_get_cursor(0))
			)
			check(name, false, (ok and "timed out" or tostring(res)) .. state)
			return finish()
		end
		vim.defer_fn(tick, 50)
	end
	tick()
end

local function feed(keys)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "m", false)
end

local path = "documents/Assets/statement-2024-07.pdf"

--- Fire the chord via `entry` (keys that enter insert mode), fuzzy-filter
--- the picker down to the statement, confirm, and assert the path landed at
--- `want_line` with typing resuming right after it (`want_after_x`).
local function scenario(name, entry, want_line, want_after_x, next_step)
	feed(entry .. "<C-x><C-f>")
	local picker
	poll(name .. ": picker opens", function()
		picker = Snacks.picker.get()[1]
		return picker ~= nil
	end, function()
		poll(name .. ": finder lists files", function()
			return not picker:is_active() and #picker:items() > 0
		end, function()
			-- Sparse on purpose: subsequence, not substring, so this is the
			-- fuzzy matching the mapping exists for.
			picker.input:set("stmnt2024")
			-- :items() is the *filtered* list (:count() stays the finder's
			-- total), so this is what the matcher actually kept.
			poll(name .. ": fuzzy match narrows to one", function()
				local matched = picker:items()
				return not picker:is_active() and #matched == 1 and matched[1].file == path
			end, function()
				picker:action("confirm")
				-- Mode is polled with the line: the keymap resumes insert via
				-- a queued key, which only lands back in the main loop.
				poll(name .. ": path inserted, insert mode restored", function()
					return line() == want_line and vim.api.nvim_get_mode().mode == "i"
				end, function()
					-- The proof the cursor came back to the right byte: one
					-- more typed character lands after the path, nowhere else.
					feed("X")
					poll(name .. ": typing resumes after the path", function()
						return line() == want_after_x
					end, function()
						-- Picker teardown keeps running on timers after the
						-- confirm; a late stopinsert must not throw the user
						-- back to normal mode mid-word.
						vim.defer_fn(function()
							check(
								name .. ": insert mode survives picker teardown",
								vim.api.nvim_get_mode().mode == "i",
								vim.api.nvim_get_mode().mode
							)
							next_step()
						end, 600)
					end, 5000)
				end)
			end)
		end)
	end)
end

local ok, err = pcall(function()
	vim.fn.mkdir(vim.fs.dirname(dir .. "/" .. path), "p")
	assert(io.open(dir .. "/" .. path, "w")):close()
	assert(io.open(dir .. "/README.md", "w")):close()
	vim.cmd.cd(dir)
	vim.cmd.edit(dir .. "/ledger.beancount")
end)
check("setup", ok, err)
if not ok then
	return finish()
end

-- The mapping loads with the rest of config/keymaps.lua on VeryLazy — which
-- lazy.nvim hangs off UIEnter, an event a headless run never sees. Fire it
-- the way lazy.nvim's very_lazy() would.
if not vim.g.did_very_lazy then
	vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
end
poll("mapping exists", function()
	return vim.fn.maparg("<C-X><C-F>", "i") ~= ""
end, function()
	-- Mid-line: the path has to land between the quotes and typing has to
	-- resume before the closing quote, not at end of line.
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'document: ""' })
	vim.api.nvim_win_set_cursor(0, { 1, 11 })
	scenario(
		"mid-line",
		"i",
		'document: "' .. path .. '"',
		'document: "' .. path .. 'X"',
		function()
			-- End of line: appending must not stumble over the normal-mode
			-- cursor never resting past the last byte.
			feed("<Esc>")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "document: " })
			scenario("end-of-line", "A", "document: " .. path, "document: " .. path .. "X", finish)
		end
	)
end)
