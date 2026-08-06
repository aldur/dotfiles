---@brief
---
-- `journal_file` is resolved per buffer, for a
-- tree that holds several of them side by side:
--
--   root/{a,b}.beancount          the ledgers, each its own root
--   root/{comm,prices}.beancount  shared definitions, self-contained
--   root/includes/{a,b}/...       fragments belonging to one ledger
local function beancount_ledger(name)
	local ws = vim.fs.root(name, { "includes", ".git" })
	if not ws then
		return nil, nil
	end
	local rel = vim.fs.relpath(ws, name)
	return ws, rel and rel:match("^includes/([^/]+)/")
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
		local journal = vim.fs.joinpath(ws, ledger .. ".beancount")
		if vim.uv.fs_stat(journal) then
			extra.journal_file = journal
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
}
