-- lazy.nvim through the nix store — a nix-only slimming of the lazyCat
-- template from nixCats' luaUtils: no git bootstrap, dev-mode resolves every
-- plugin from the store's pack dir, and the rtp is rebuilt by hand because
-- lazy's own reset would drop the nixCats entries.
local M = {}

---Like require('lazy').setup(specs, opts), with the store path of lazy.nvim
---as an extra first argument.
function M.setup(nixLazyPath, lazySpecs, lazyCFG)
	local nixCats = require("nixCats")
	local myNeovimPackages = nixCats.vimPackDir .. "/pack/myNeovimPackages"

	lazyCFG = vim.tbl_deep_extend("force", lazyCFG or {}, {
		performance = {
			rtp = {
				reset = false,
			},
		},
		dev = {
			path = function(plugin)
				for _, kind in ipairs({ "start", "opt" }) do
					local path = myNeovimPackages .. "/" .. kind .. "/" .. plugin.name
					if vim.fn.isdirectory(path) == 1 then
						return path
					end
				end
				return "~/projects/" .. plugin.name
			end,
			patterns = { "" },
			fallback = true,
		},
	})

	local cfgdir = nixCats.configDir
	vim.opt.rtp = {
		cfgdir,
		nixCats.nixCatsPath,
		nixCats.pawsible.allPlugins.ts_grammar_path,
		vim.fn.stdpath("data") .. "/site",
		nixLazyPath,
		vim.env.VIMRUNTIME,
		vim.fn.fnamemodify(vim.v.progpath, ":p:h:h") .. "/lib/nvim",
		cfgdir .. "/after",
	}

	require("lazy").setup(lazySpecs, lazyCFG)
end

return M
