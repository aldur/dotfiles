-- In-editor assertions for the built editor, driven by checks/lazyvim-variants.nix.
--
-- Everything here is a thing that has actually broken: a grammar shipped
-- without the queries that make it paint, a formatter configured in lua whose
-- binary never made it into the category, a server whose `root_dir` throws
-- before it can attach. The build-side checks cannot see any of it — the store
-- paths are all present and correct — so it has to be asserted from inside a
-- running editor.
--
-- The variant's expectations arrive as JSON in $PROBE_SPEC; $PROBE_DIR is a
-- scratch directory. Prints one FAIL line per broken assertion and PROBE-OK
-- when there are none.

local spec = vim.json.decode(vim.env.PROBE_SPEC)
local dir = vim.env.PROBE_DIR

local failures = {}
local function check(name, ok, detail)
	if not ok then
		table.insert(failures, ("FAIL %s%s"):format(name, detail and (" — " .. tostring(detail)) or ""))
	end
end

--- Run `body`, then report and quit whatever happened. Reporting has to be
--- unconditional: nvim keeps running after a script aborts, so an escaping
--- error would turn a failed assertion into a hung build.
local function report(body)
	local ok, err = pcall(body)
	check("probe ran to completion", ok, err)
	io.write(#failures == 0 and "PROBE-OK\n" or (table.concat(failures, "\n") .. "\n"))
	vim.cmd("qa!")
end

report(function()
	--- Write `text` to `dir/name` and open it. Formatters and treesitter both key
	--- off a buffer backed by a real file: conform refuses to run a non-stdin
	--- formatter on an unsaved buffer, and filetype detection wants the extension.
	---
	--- The edit is guarded because this is where the editor breaks loudest: a
	--- server resolving its root through a toolchain that is not installed throws
	--- from inside a FileType autocmd, and an error escaping to the top level here
	--- would skip the report and leave nvim running until the build times out.
	local function open(name, text)
		local path = dir .. "/" .. name
		local fh = assert(io.open(path, "w"))
		fh:write(text)
		fh:close()
		local ok, err = pcall(vim.cmd.edit, path)
		check("opens " .. name, ok, err)
		return vim.api.nvim_get_current_buf()
	end

	-- Plugins are lazy-loaded on events a headless run may never see.
	require("lazy").load({ plugins = { "nvim-treesitter", "conform.nvim" } })

	-- Every grammar on the runtimepath, discovered rather than enumerated so a
	-- grammar added to a category is covered without touching this file.
	local langs = {}
	do
		local seen = {}
		for _, p in ipairs(vim.api.nvim_get_runtime_file("parser/*.so", true)) do
			local lang = vim.fn.fnamemodify(p, ":t:r")
			if not seen[lang] then
				seen[lang] = true
				table.insert(langs, lang)
			end
		end
		table.sort(langs)
	end

	check(("grammar count >= %d"):format(spec.min_grammars), #langs >= spec.min_grammars, #langs .. " found")

	for _, lang in ipairs(spec.present_grammars) do
		check("grammar present: " .. lang, vim.list_contains(langs, lang))
	end
	-- The light/full split and the treesitterAll denylist, from the other side: a
	-- grammar that should have been left out must not have crept back in.
	for _, lang in ipairs(spec.absent_grammars) do
		check("grammar absent: " .. lang, not vim.list_contains(langs, lang))
	end

	for _, lang in ipairs(langs) do
		local loaded, lerr = pcall(vim.treesitter.language.add, lang)
		check("parser loads: " .. lang, loaded, lerr)

		-- The regression this whole file exists for: nixpkgs ships a grammar's
		-- parser and its queries as two plugins, and a parser whose queries were
		-- left behind attaches to the buffer and paints nothing at all.
		local got, query = pcall(vim.treesitter.query.get, lang, "highlights")
		check("highlights query: " .. lang, got and query ~= nil, got and "no query on the runtimepath" or query)

		-- The rest need not exist, but a query that fails to *compile* means the
		-- parser and its queries drifted apart across a bump.
		for _, kind in ipairs({ "indents", "folds", "injections", "locals" }) do
			local ok, err = pcall(vim.treesitter.query.get, lang, kind)
			check(("%s query compiles: %s"):format(kind, lang), ok, err)
		end
	end

	-- Resolving a query proves it parses; only a real buffer proves the editor
	-- reaches it. LazyVim decides whether to start the highlighter from
	-- nvim-treesitter's `get_installed`, which init.lua patches to look at the
	-- runtimepath — so this covers that patch as well as the queries.
	for _, sample in ipairs(spec.samples) do
		local buf = open("sample." .. sample.ext, sample.text)
		local attached = vim.wait(30000, function()
			return vim.treesitter.highlighter.active[buf] ~= nil
		end, 50)
		check("highlighter attaches: " .. sample.lang, attached, "filetype " .. vim.bo[buf].filetype)

		local captured = false
		for row = 0, vim.api.nvim_buf_line_count(buf) - 1 do
			local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
			for col = 0, math.max(#line - 1, 0) do
				local ok, captures = pcall(vim.treesitter.get_captures_at_pos, buf, row, col)
				if ok and #captures > 0 then
					captured = true
					break
				end
			end
			if captured then
				break
			end
		end
		check("highlights captured: " .. sample.lang, captured)
	end

	-- Formatting end to end. LazyVim's extras configure a superset of what the
	-- editor ships and conform quietly skips whatever is missing, so asking
	-- whether each formatter is `available` proves nothing: run them and compare
	-- the buffer. `lsp_format = "never"` keeps this about the shipped binaries.
	for _, case in ipairs(spec.formats) do
		open("format." .. case.ext, case.input)
		local ok, err = pcall(require("conform").format, {
			bufnr = 0,
			async = false,
			lsp_format = "never",
			timeout_ms = 30000,
		})
		check("format runs: " .. case.ext, ok, err)
		local got = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		check("format result: " .. case.ext, got == case.want, ("got %q want %q"):format(got, case.want))
	end

	-- The spell plugin builds a runtimepath entry out of fetched .spl/.sug files;
	-- 'encoding' is hardwired to utf-8, so only those variants can ever load.
	-- Checking a word rather than the file's presence proves nvim read it.
	for _, case in ipairs(spec.spells) do
		check(
			"spellfile on runtimepath: " .. case.lang,
			#vim.api.nvim_get_runtime_file("spell/" .. case.lang .. ".utf-8.spl", true) > 0
		)
		local ok, err = pcall(vim.cmd, "setlocal spell spelllang=" .. case.lang)
		check("spelllang loads: " .. case.lang, ok, err)
		if ok then
			local _, known = pcall(vim.fn.spellbadword, case.known)
			local _, bad = pcall(vim.fn.spellbadword, case.unknown)
			check("spell knows " .. case.known, known and known[1] == "", vim.inspect(known))
			check("spell flags " .. case.unknown, bad and bad[1] == case.unknown, vim.inspect(bad))
		end
	end

	-- Grammars come from nix, so the commands that would download one are stubs.
	-- Left live they write into the install dir and shadow the store parsers.
	for _, cmd in ipairs({ "TSInstall", "TSUpdate", "TSUninstall" }) do
		check(cmd .. " is defined", vim.fn.exists(":" .. cmd) == 2)
		local notified
		local notify = vim.notify
		vim.notify = function(msg, level)
			notified = { msg = msg, level = level }
		end
		local ok, err = pcall(vim.cmd, cmd .. " bash")
		vim.notify = notify
		check(cmd .. " runs without error", ok, err)
		check(
			cmd .. " warns instead of installing",
			notified ~= nil and notified.level == vim.log.levels.WARN,
			vim.inspect(notified)
		)
	end

	-- after/ftplugin rides in the config directory rather than a plugin, so it is
	-- the first thing to disappear if the packaged lua tree changes shape.
	do
		local buf = open("ledger.beancount", '2024-01-01 open Assets:Cash USD\n\n2024-01-02 * "S" "T"\n')
		check("beancount filetype", vim.bo[buf].filetype == "beancount", vim.bo[buf].filetype)
		check("beancount commentstring", vim.bo[buf].commentstring == "; %s", vim.bo[buf].commentstring)
		check("beancount reconcile mapping", vim.fn.maparg("mc", "n") ~= "")

		-- Both directions: the option is buffer-local, so setting the global one
		-- misses this buffer and follows into every buffer opened afterwards.
		local function has_colon(b)
			return vim.bo[b].iskeyword:find(":", 1, true) ~= nil
		end
		check("beancount iskeyword takes ':'", has_colon(buf), vim.bo[buf].iskeyword)
		local after = open("after.lua", "local x = 1\n")
		check("iskeyword stays out of other buffers", not has_colon(after), vim.bo[after].iskeyword)
	end

	-- Anything that threw along the way. A server whose `root_dir` shells out to a
	-- toolchain that is not there takes this path: the file opens, nothing
	-- attaches, and the only trace is a stack dump in :messages.
	do
		local messages = vim.api.nvim_exec2("messages", { output = true }).output
		for _, pattern in ipairs({ "stack traceback", "Error executing" }) do
			check("no lua errors in :messages (" .. pattern .. ")", not messages:find(pattern, 1, true), messages)
		end
	end
end)
