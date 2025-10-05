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
			opts = {
				ensure_installed = lazyAdd("all", {}),
				auto_install = lazyAdd(true, false),
				sync_install = lazyAdd(true, false),
				-- TinyMD.nvim does a better job at indenting lists.
				indent = { disable = { "markdown" } },
			},
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
