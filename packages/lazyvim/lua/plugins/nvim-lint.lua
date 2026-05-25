-- nvim-lint configuration for forge linters
return {
	{
		"mfussenegger/nvim-lint",
		opts = {
			linters_by_ft = {
				solidity = { "forge-lint" },
			},
			linters = {
				["forge-lint"] = require("lint.forge-lint"),
			},
		},
	},
}
