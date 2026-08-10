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

	-- The light half of the split: a grammar that rides `treesitterAll` must not
	-- have found its way into the build that does not carry it. Which grammars
	-- *are* shipped is the build's business, so the set goes out as data for the
	-- check to compare between variants rather than being matched against a list
	-- restated here.
	for _, lang in ipairs(spec.absent_grammars) do
		check("grammar absent: " .. lang, not vim.list_contains(langs, lang))
	end
	io.write("PROBE-LANGS: " .. table.concat(langs, " ") .. "\n")

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

		-- The highlighter parses in the background after it attaches (Nvim
		-- 0.12), and get_captures_at_pos only reads trees that are already
		-- parsed. A parse call without a callback is synchronous, so one
		-- call here makes the scan below deterministic; `true` also parses
		-- the injected languages.
		pcall(function()
			vim.treesitter.get_parser(buf):parse(true)
		end)
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

	-- Nothing downloads at runtime. Mason is disabled and TSInstall is a stub
	-- (asserted below); lazy's luarocks support has to stay off too — enabled,
	-- the first spec with a rockspec makes lazy bootstrap hererocks.
	check("lazy rocks support is off", require("lazy.core.config").options.rocks.enabled == false)

	-- The wrapper ships no host interpreters, so every provider must be off:
	-- one left on probes for its interpreter on each checkhealth. All four
	-- ride `settings.hosts` (see lazyvim.nix) — nixCats only emits the
	-- disable for hosts it is told about.
	for _, provider in ipairs({ "python3", "node", "perl", "ruby" }) do
		check("provider disabled: " .. provider, vim.g["loaded_" .. provider .. "_provider"] == 0)
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
		-- The mapping needs the same treatment: `maparg` sees a global map from
		-- any buffer, so an empty result here proves the map is buffer-local.
		check("reconcile mapping stays out of other buffers", vim.fn.maparg("mc", "n") == "")
	end

	-- The beancount client is wired in this repo (packages/lazyvim/lsp/
	-- beancount.lua) rather than taken from lspconfig: a `root_dir` that puts each
	-- ledger on its own client, a `before_init` that hands that client its journal
	-- and bean-check, and a diagnostics handler that drops paths outside the
	-- ledger. The server binary rides a category that is off by default, so `cmd`
	-- is swapped for an in-process one — what is under test is this repo's lua,
	-- and a fake server can also push the diagnostics a real one would only emit
	-- from a ledger that is already broken.
	do
		local beans = dir .. "/beans"
		local function put(rel, text)
			local path = beans .. "/" .. rel
			vim.fn.mkdir(vim.fs.dirname(path), "p")
			local fh = assert(io.open(path, "w"))
			fh:write(text)
			fh:close()
			return path
		end

		-- Two ledgers side by side, one with a fragment, plus the file that must
		-- never pull a client. `includes/` is what roots the workspace, and the
		-- fragments in it are `.include`: nothing in neovim maps that extension,
		-- so they carry the modeline that names the filetype, as the real ones do.
		local modeline = "; vim: set ft=beancount:\n"
		put("index.beancount", "2024-01-01 open Assets:Cash USD\n")
		put("heartbit.beancount", "2024-01-01 open Assets:Bank USD\n")
		put("includes/index/amex.include", modeline .. '2024-01-02 * "S" "T"\n')
		put("prices.include", modeline .. "2024-01-01 price EUR 1.00 USD\n")
		put("importer.py", "x = 1\n")
		put(".venv/bin/bean-check", "")

		-- lua/lsp.lua enables a server only when its binary is there, so that a
		-- missing one stays quiet instead of failing validation on every FileType
		-- event. The category that ships this one is off by default, which makes
		-- the probe the place that proves the gate holds.
		check(
			"beancount stays disabled without its binary",
			vim.fn.executable("beancount-language-server") == 1 or not vim.lsp.is_enabled("beancount")
		)

		-- One record per client, keyed by the root it initialised with; the
		-- dispatchers come with it so the diagnostics handler can be driven.
		local seen = {}
		vim.lsp.config("beancount", {
			cmd = function(dispatchers)
				local rec, closing = { dispatchers = dispatchers }, false
				return {
					request = function(method, params, callback)
						if method == "initialize" then
							rec.init = params.initializationOptions
							seen[vim.uri_to_fname(params.rootUri)] = rec
							callback(nil, { capabilities = {} })
						elseif method == "shutdown" then
							callback(nil, nil)
						end
						return true, 1
					end,
					notify = function(method)
						closing = closing or method == "exit"
						return true
					end,
					is_closing = function()
						return closing
					end,
					terminate = function()
						closing = true
					end,
				}
			end,
		})

		-- The gate above keeps it out of the enabled set on a build without the
		-- server; everything below is about this repo's lua, so enable it by hand
		-- now that `cmd` no longer needs one.
		vim.lsp.enable("beancount")

		local function beancount_client(buf)
			local function found()
				return vim.lsp.get_clients({ bufnr = buf, name = "beancount" })[1]
			end
			vim.wait(10000, function()
				return found() ~= nil
			end, 50)
			return found()
		end

		--- Open `rel` and return the beancount client that attached to it, if any.
		local function attach(rel)
			local ok, err = pcall(vim.cmd.edit, beans .. "/" .. rel)
			check("opens " .. rel, ok, err)
			return beancount_client(vim.api.nvim_get_current_buf())
		end

		-- Each ledger on its own root, and the journal that root stands for.
		-- Sharing a root would leave whichever ledger opened first deciding
		-- `journal_file` for both, which the server only reveals as diagnostics
		-- against the wrong book.
		for _, case in ipairs({ { "index.beancount", "index" }, { "heartbit.beancount", "heartbit" } }) do
			local rel, ledger = case[1], case[2]
			local client = attach(rel)
			check("beancount attaches: " .. rel, client ~= nil)
			if client then
				local want = beans .. "/includes/" .. ledger
				check(("root for %s"):format(rel), client.config.root_dir == want, client.config.root_dir)
				local init = (seen[want] or {}).init or {}
				check(
					("journal_file for %s"):format(rel),
					init.journal_file == beans .. "/" .. rel,
					vim.inspect(init.journal_file)
				)
				-- Rooting below the workspace puts `.venv` out of the server's own
				-- reach, and a checker it cannot find is a silent no-diagnostics.
				check(
					("bean_check_cmd for %s"):format(rel),
					(init.bean_check or {}).bean_check_cmd == beans .. "/.venv/bin/bean-check",
					vim.inspect(init.bean_check)
				)
			end
		end

		local index = seen[beans .. "/includes/index"]
		check("two ledgers, two clients", seen[beans .. "/includes/heartbit"] ~= nil and index ~= nil)

		-- A fragment belongs to its ledger's client, not to one of its own.
		do
			local client = attach("includes/index/amex.include")
			check("beancount attaches: fragment", client ~= nil)
			if client then
				check(
					"fragment shares its ledger's root",
					client.config.root_dir == beans .. "/includes/index",
					client.config.root_dir
				)
			end
		end

		-- Self-contained shared definitions: their own ledger, and `journal_file`
		-- has to fall through to `.include` because no `prices.beancount` exists.
		do
			local client = attach("prices.include")
			check("beancount attaches: prices.include", client ~= nil)
			if client then
				local init = (seen[beans .. "/includes/prices"] or {}).init or {}
				check(
					"journal_file falls through to .include",
					init.journal_file == beans .. "/prices.include",
					vim.inspect(init.journal_file)
				)
			end
		end

		-- The regression this section exists for. `filetypes` is inherited from
		-- lspconfig, and a config resolved without it means "ALL filetypes" — so
		-- a python file next to the ledger is exactly what would attach.
		for _, rel in ipairs({ "importer.py" }) do
			local ok = pcall(vim.cmd.edit, beans .. "/" .. rel)
			local buf = vim.api.nvim_get_current_buf()
			vim.wait(500)
			check(
				"beancount stays off " .. rel,
				ok and vim.lsp.get_clients({ bufnr = buf, name = "beancount" })[1] == nil,
				vim.bo[buf].filetype
			)
		end

		-- Diagnostics are published per path, not per attached buffer: neovim
		-- `bufadd`s whatever the server names. A path outside the ledger must not
		-- reach that, and — since it would land outside the server's forest too —
		-- would otherwise never be cleared again.
		if index then
			local function publish(path)
				index.dispatchers.notification("textDocument/publishDiagnostics", {
					uri = vim.uri_from_fname(path),
					diagnostics = {
						{
							range = {
								start = { line = 0, character = 0 },
								["end"] = { line = 0, character = 1 },
							},
							message = "probe",
							severity = 1,
						},
					},
				})
				vim.wait(500)
			end

			-- Neither file is open, so a buffer existing afterwards is the handler's
			-- doing and nothing else's.
			local stray = beans .. "/never-opened.py"
			publish(stray)
			check("stray .py diagnostic dropped", vim.fn.bufexists(stray) == 0)

			-- `.include` has to survive the filter: bean-check reports real errors
			-- in fragments, and dropping those would trade one silent failure for
			-- another.
			local include = beans .. "/includes/index/never-opened.include"
			publish(include)
			check(
				"ledger .include diagnostic kept",
				vim.fn.bufexists(include) == 1 and #vim.diagnostic.get(vim.fn.bufnr(include)) > 0
			)
		end
	end

	-- forge lint, unit then wired. The parser reads two shapes off one stderr
	-- stream: rustc-style JSON for lint notes — stable across forge versions,
	-- where the human rendering changed between 1.5 (` --> `) and 1.7 (`╭▸`) —
	-- and text for compiler errors, which is identical on both. The editor
	-- deliberately ships no forge (projects bring it through direnv), so a
	-- stub stands in for the wired half.
	do
		local linter = require("lint.forge-lint")
		local proj = dir .. "/forgeproj"
		local sol = proj .. "/src/Probe.sol"

		-- The condition gates on both halves; this build has no forge.
		check("forge-lint off without forge", not linter.condition({ filename = sol }))

		-- The note as every forge emits it under `--json`, encoded rather
		-- than quoted so the shape under test is readable.
		local note = vim.json.encode({
			["$message_type"] = "diagnostic",
			message = "mutable variables should use mixedCase",
			code = { code = "mixed-case-variable" },
			level = "note",
			spans = {
				{
					file_name = "src/Probe.sol",
					line_start = 4,
					line_end = 4,
					column_start = 10,
					column_end = 21,
					is_primary = true,
				},
			},
		})

		local function parsed(output, name)
			return linter.parser(output, vim.fn.bufadd(name))
		end

		-- The JSON note, shifted to 0-indexed and end-exclusive.
		local diags = parsed(note .. "\n", sol)
		check("json note parses", #diags == 1, vim.inspect(diags))
		if #diags == 1 then
			local d = diags[1]
			check(
				"json note fields",
				d.lnum == 3
					and d.col == 9
					and d.end_col == 20
					and d.severity == vim.diagnostic.severity.HINT
					and d.code == "mixed-case-variable",
				vim.inspect(d)
			)
		end

		-- Compiler errors stay text, with the trailing colon.
		local errout = "Error: Compiler run failed:\nError (7576): Undeclared identifier.\n --> src/Probe.sol:4:27:\n"
		diags = parsed(errout, sol)
		check(
			"compiler error parses",
			#diags == 1 and diags[1].severity == vim.diagnostic.severity.ERROR and diags[1].code == "7576",
			vim.inspect(diags)
		)

		-- The path boundary: `foosrc/Probe.sol` must not take `src/Probe.sol`'s.
		check("forge-lint path boundary holds", #parsed(note .. "\n", proj .. "/foosrc/Probe.sol") == 0)

		-- The wired half: LazyVim's condition, nvim-lint's spawn, the stderr
		-- stream and the parser, ending in published diagnostics. The stub
		-- prints the note above, so the assertion closes the whole loop.
		local function put(rel, text, mode)
			local path = proj .. "/" .. rel
			vim.fn.mkdir(vim.fs.dirname(path), "p")
			local fh = assert(io.open(path, "w"))
			fh:write(text)
			fh:close()
			if mode then
				vim.uv.fs_chmod(path, mode)
			end
			return path
		end
		put("fixture.jsonl", note .. "\n")
		put("foundry.toml", '[profile.default]\nsrc = "src"\n')
		put("bin/forge", "#!/bin/sh\ncat " .. proj .. "/fixture.jsonl >&2\n", 493)
		put(
			"src/Probe.sol",
			"// SPDX-License-Identifier: MIT\npragma solidity ^0.8.0;\ncontract Probe {\n    uint valid_until;\n}\n"
		)

		require("lazy").load({ plugins = { "nvim-lint" } })
		local path_env = vim.env.PATH
		vim.env.PATH = proj .. "/bin:" .. path_env

		check("forge-lint on inside a project", linter.condition({ filename = sol }))

		local opened, oerr = pcall(vim.cmd.edit, sol)
		check("opens Probe.sol", opened, oerr)
		local buf = vim.api.nvim_get_current_buf()
		-- BufWritePost is one of LazyVim's lint events, and by now the plugin
		-- is loaded, so the autocmd is there to fire.
		vim.cmd.write()
		local function forge_diags(b)
			return vim.tbl_filter(function(d)
				return d.source == "forge-lint"
			end, vim.diagnostic.get(b))
		end
		local landed = vim.wait(15000, function()
			return #forge_diags(buf) > 0
		end, 100)
		check("forge-lint publishes", landed, vim.inspect(vim.diagnostic.get(buf)))
		if landed then
			local d = forge_diags(buf)[1]
			check("published note", d.lnum == 3 and d.code == "mixed-case-variable", vim.inspect(d))
		end

		-- Outside a project the condition keeps forge from spawning at all.
		-- Before the gate, every lint pass here raised "Error running forge".
		local stray = dir .. "/stray.sol"
		local fh = assert(io.open(stray, "w"))
		fh:write("pragma solidity ^0.8.0;\n")
		fh:close()
		opened, oerr = pcall(vim.cmd.edit, stray)
		check("opens stray.sol", opened, oerr)
		local sbuf = vim.api.nvim_get_current_buf()
		vim.cmd.write()
		vim.wait(1500)
		check("no forge-lint outside a project", #forge_diags(sbuf) == 0, vim.inspect(vim.diagnostic.get(sbuf)))
		local messages = vim.api.nvim_exec2("messages", { output = true }).output
		check("no 'Error running forge'", not messages:find("Error running forge", 1, true), messages)

		vim.env.PATH = path_env
	end

	-- A host without a wiki: $HOME here has no notes directory, so the spec's
	-- init leaves `g:wiki_root` alone and wiki.vim's own load turns the unset
	-- variable into "". Startup and the pickers both have to stay quiet — the
	-- pages picker once globbed `**/*.md` from `/` when handed "".
	do
		check("wiki root stays unset without a wiki", (vim.g.wiki_root or "") == "", vim.inspect(vim.g.wiki_root))
		local messages = vim.api.nvim_exec2("messages", { output = true }).output
		check("no wiki_root warning at startup", not messages:find("wiki_root", 1, true), messages)

		require("lazy").load({ plugins = { "snacks.nvim", "wiki.vim" } })
		local notified
		local orig = vim.notify
		vim.notify = function(msg)
			notified = msg
		end
		local ok, err = pcall(require("wiki.snacks").pages)
		vim.notify = orig
		check("pages() runs without a root", ok, err)
		check("pages() refuses without a root", notified == "wiki_root is not set", vim.inspect(notified))
		check("pages() opens no picker", #require("snacks").picker.get() == 0)
	end

	-- Visual-mode link insertion must consume the selection and make it the link
	-- text. `wiki#link#add` does that itself when it gets the "visual" mode, and
	-- it is the only thing that can: the mapping leaves visual mode before the
	-- lua runs, so a `normal! "wd` there is an operator with no motion and does
	-- nothing at all. The selection then stayed in the buffer and the link text
	-- came from whatever register `w` held from some earlier edit.
	do
		local wiki = dir .. "/wiki"
		vim.fn.mkdir(wiki, "p")
		for name, text in pairs({ ["note.md"] = "keep this text\n", ["target.md"] = "# target\n" }) do
			local fh = assert(io.open(wiki .. "/" .. name, "w"))
			fh:write(text)
			fh:close()
		end

		require("lazy").load({ plugins = { "snacks.nvim", "wiki.vim" } })
		vim.g.wiki_root = wiki
		local opened, oerr = pcall(vim.cmd.edit, wiki .. "/note.md")
		check("opens the wiki page", opened, oerr)
		local buf = vim.api.nvim_get_current_buf()

		-- Register `w` is the one wiki.vim cuts into. Fill it first: if the link
		-- text comes from here rather than from the selection, this is what shows.
		vim.fn.setreg("w", "STALE")

		-- The `xnoremap` that calls this leaves visual mode first, so by now the
		-- selection is only the `'<` and `'>` marks.
		vim.cmd("normal! ggv$")
		vim.cmd([[execute "normal! \<Esc>"]])

		local ok, lerr = pcall(require("wiki.snacks").links, "visual")
		check("visual link picker runs", ok, lerr)
		local pickers = require("snacks").picker.get
		vim.wait(5000, function()
			return #pickers() > 0
		end, 50)
		-- Without this the assertions below also pass when the picker never opens.
		check("visual link picker is open", #pickers() > 0)

		for _, picker in ipairs(pickers()) do
			pcall(function()
				picker:action("confirm")
			end)
		end
		vim.wait(2000, function()
			return #pickers() == 0
		end, 50)

		local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
		check("visual link takes its text from the selection", line:match("^%[keep this text%]%(") ~= nil, line)
		check("visual link does not read a stale register", not line:find("STALE", 1, true), line)
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
