local lazyOptions = { lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json" }

-- The lazy wrapper: require('lazy').setup(), with the store path of
-- lazy.nvim as an extra first argument.
require("lazyCat").setup(
	nixCats.pawsible({
		"allPlugins",
		"start",
		"lazy.nvim",
	}),
	{
		{ "LazyVim/LazyVim", import = "lazyvim.plugins" },

		-- Import extras, as per `lazyvim_check_order`
		{ import = "plugins.lazy_extras" },

		-- Mason downloads mutable binaries; nix provides them instead.
		{ "mason-org/mason-lspconfig.nvim", enabled = false },
		{ "mason-org/mason.nvim", enabled = false },

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
			opts_extend = false,
			opts = function(_, opts)
				opts.ensure_installed = {}
				-- TinyMD.nvim does a better job at indenting lists.
				opts.indent = vim.tbl_deep_extend("force", opts.indent or {}, { disable = { "markdown" } })

				-- Grammars are on the runtimepath but nvim-treesitter's
				-- get_installed only checks its own install_dir. Patch it to
				-- also discover parsers/queries from the runtimepath, so that
				-- LazyVim's `have()` returns true and enables
				-- highlights/indents/folds.
				local config = require("nvim-treesitter.config")
				local orig_get_installed = config.get_installed
				---@diagnostic disable-next-line: duplicate-set-field
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

				for _, cmd in ipairs({ "TSInstall", "TSUpdate", "TSUninstall" }) do
					pcall(vim.api.nvim_del_user_command, cmd)
					vim.api.nvim_create_user_command(cmd, function()
						vim.notify(
							cmd .. ": grammars come from nix; edit the lazyvim categories instead.",
							vim.log.levels.WARN
						)
					end, { nargs = "*", desc = "Disabled: grammars come from nix" })
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
