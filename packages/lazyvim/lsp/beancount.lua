---@brief
---
-- `journal_file` is resolved per buffer, for a
-- tree that holds several of them side by side:
--
--   root/{a,b}.beancount          the ledgers, each its own root
--   root/{comm,prices}.beancount  shared definitions, self-contained
--   root/includes/{a,b}/...       fragments belonging to one ledger
--
-- A fragment names its ledger through the directory it sits in, a journal
-- through its own basename. Both have to resolve: a journal that comes back
-- without one roots at the workspace, `before_init` finds no ledger to build a
-- `journal_file` from, and the server falls back to bean-checking whatever
-- single file it was handed.
local function beancount_ledger(name)
	local ws = vim.fs.root(name, { "includes", ".git" })
	if not ws then
		return nil, nil
	end
	local rel = vim.fs.relpath(ws, name)
	if not rel then
		return ws, nil
	end
	local ledger = rel:match("^includes/([^/]+)/")
	if ledger then
		return ws, ledger
	end
	-- `.include` as well as `.beancount`: the self-contained top-level files
	-- carry that extension.
	return ws, rel:match("^([^/]+)%.beancount$") or rel:match("^([^/]+)%.include$")
end

---@type vim.lsp.Config
return {
	init_options = {
		diagnostic_flags = { "!", "?" },
		bean_check = { method = "system" },
	},

	-- One client per ledger: `init_options` is sent once at initialize, so the
	-- fragments of `a` and `b` have to land on different roots to get different
	-- `journal_file`s. A `root_dir` function also wins over the inherited
	-- `root_markers`, which would otherwise root everything at the git repo.
	--
	-- `includes/<ledger>` is the root for the ledger *and* its fragments, which
	-- puts `a.beancount` and `b.beancount` on separate clients even though they
	-- are siblings. The directory need not exist: nothing reads it once
	-- `journal_file` is set, and the alternative is a shared root where whichever
	-- ledger opens first decides the journal for both.
	root_dir = function(bufnr, on_dir)
		local name = vim.api.nvim_buf_get_name(bufnr)
		local ws, ledger = beancount_ledger(name)
		if not ws then
			on_dir(vim.fs.dirname(name))
		elseif ledger then
			on_dir(vim.fs.joinpath(ws, "includes", ledger))
		else
			on_dir(ws)
		end
	end,

	before_init = function(params, _)
		-- Typed as `lsp.LSPAny`, and Neovim sends `vim.NIL` rather than nil when
		-- there is no folder -- which is truthy, so a plain `if params.rootUri`
		-- would wave it through into `uri_to_fname`.
		local root_uri = params.rootUri
		if type(root_uri) ~= "string" then
			return
		end
		local root = vim.uri_to_fname(root_uri)
		-- Not `root and root:match(...)`: `and` truncates to a single value, so
		-- the second capture would silently come back nil.
		local ws, ledger = root:match("^(.*)/includes/([^/]+)$")
		if not ws then
			return
		end

		local extra = {}
		for _, ext in ipairs({ ".beancount", ".include" }) do
			local journal = vim.fs.joinpath(ws, ledger .. ext)
			if vim.uv.fs_stat(journal) then
				extra.journal_file = journal
				break
			end
		end
		-- Rooting at includes/<ledger> puts the ledger's `.venv` out of reach of
		-- the server's own lookup, and that failure is silent -- no checker means
		-- no diagnostics at all, which reads exactly like a clean file.
		local bean_check = vim.fs.joinpath(ws, ".venv", "bin", "bean-check")
		if vim.uv.fs_stat(bean_check) then
			extra.bean_check = { bean_check_cmd = bean_check }
		end

		-- Assign rather than mutate: `init_options` is one table shared by every
		-- client of this config, so an in-place write would leak `a`'s journal
		-- into `b`'s client. Same `vim.NIL` caveat as above, hence the type test
		-- rather than `or {}`.
		local init = params.initializationOptions
		params.initializationOptions = vim.tbl_deep_extend("force", type(init) == "table" and init or {}, extra)
	end,

	handlers = {
		-- The server forwards whatever paths `bean-check` printed, including ones
		-- that are not beancount at all -- its own publisher calls them "the broken
		-- file paths" and sends them anyway. Neovim's handler then `bufadd`s the
		-- file and sets the diagnostics without checking that the client is
		-- attached, so a stray path lands in an unrelated buffer; and because such
		-- a file is never in the server's forest, the clearing pass skips it and
		-- the markers stay until the client is stopped.
		--
		-- `.include` is on the list even though nothing gives those files a
		-- filetype: they are part of the ledger, so bean-check reports real errors
		-- in them and dropping those would trade one silent failure for another.
		[vim.lsp.protocol.Methods.textDocument_publishDiagnostics] = function(err, result, ctx, config)
			local uri = type(result) == "table" and result.uri
			if type(uri) == "string" then
				local ext = vim.fn.fnamemodify(vim.uri_to_fname(uri), ":e")
				if ext ~= "beancount" and ext ~= "bean" and ext ~= "include" then
					return
				end
			end
			return vim.lsp.handlers[vim.lsp.protocol.Methods.textDocument_publishDiagnostics](err, result, ctx, config)
		end,
	},
}
