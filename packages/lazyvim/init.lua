-- NOTE: this just gives nixCats global command a default value
-- so that it doesnt throw an error if you didnt install via nix.
-- usage of both this setup and the nixCats command is optional,
-- but it is very useful for passing info from nix to lua so you will likely
-- use it at least once.
require("nixCatsUtils").setup({ non_nix_value = true })

-- NOTE: You might want to move the lazy-lock.json file
local function getlockfilepath()
	if require("nixCatsUtils").isNixCats and type(nixCats.settings.unwrappedCfgPath) == "string" then
		return nixCats.settings.unwrappedCfgPath .. "/lazy-lock.json"
	else
		return vim.fn.stdpath("config") .. "/lazy-lock.json"
	end
end

local lazyOptions = { lockfile = getlockfilepath() }

-- f(a, b), a if it's _not_ nixCats, else b.
local lazyAdd = require("nixCatsUtils").lazyAdd

-- NOTE: this the lazy wrapper. Use it like require('lazy').setup() but with an extra
-- argument, the path to lazy.nvim as downloaded by nix, or nil, before the normal arguments.
require("nixCatsUtils.lazyCat").setup(
	nixCats.pawsible({
		"allPlugins",
		"start",
		"lazy.nvim",
	}),
	{
		{ "LazyVim/LazyVim", import = "lazyvim.plugins" },

		-- Import extras, as per `lazyvim_check_order`
		{ import = "plugins.lazy_extras" },

		-- Now, disable `mason` while using `nix`.
		{ "mason-org/mason-lspconfig.nvim", enabled = lazyAdd(true, false) },
		{ "mason-org/mason.nvim", enabled = lazyAdd(true, false) },

		-- Convenience to make editing `lua` files easier.
		{
			"folke/lazydev.nvim",
			opts = {
				library = {
					{
						path = (nixCats.nixCatsPath or "") .. "/lua",
						words = { "nixCats" },
					},
				},
			},
		}, -- Import remaining plugins
		{ import = "plugins" },

		-- Finally, configure `tree-sitter` _not_ to download grammars.
		-- This goes last because `lazyvim.extras` will add to `opts.ensure_installed`.
		{
			"nvim-treesitter/nvim-treesitter",
			opts_extend = lazyAdd(nil, false),
			opts = function(_, opts)
				opts.ensure_installed = lazyAdd("all", {})
				-- TinyMD.nvim does a better job at indenting lists.
				opts.indent = vim.tbl_deep_extend("force", opts.indent or {}, { disable = { "markdown" } })

				-- When installed through Nix, grammars are on the runtimepath but
				-- nvim-treesitter's get_installed only checks its own install_dir.
				-- Patch it to also discover parsers/queries from the runtimepath,
				-- so that LazyVim's `have()` returns true and enables highlights/indents/folds.
				if require("nixCatsUtils").isNixCats then
					local config = require("nvim-treesitter.config")
					local orig_get_installed = config.get_installed
					config.get_installed = function(t)
						local installed = {}
						for _, lang in ipairs(orig_get_installed(t) or {}) do
							installed[lang] = true
						end
						if t == nil or t == "parsers" then
							for _, p in ipairs(vim.api.nvim_get_runtime_file("parser/*.so", true)) do
								installed[vim.fn.fnamemodify(p, ":t:r")] = true
							end
						end
						if t == nil or t == "queries" then
							for _, p in ipairs(vim.api.nvim_get_runtime_file("queries/*", true)) do
								if vim.fn.isdirectory(p) == 1 then
									installed[vim.fn.fnamemodify(p, ":t")] = true
								end
							end
						end
						return vim.tbl_keys(installed)
					end
				end
			end,
		},
		{
			"monaqa/dial.nvim",
			opts = function(_, opts)
				table.insert(opts.groups.default, require("dial.augend").date.alias["%Y-%m-%d"])
			end,
		},
	},
	lazyOptions
)

require("lsp")
require("terminal")
