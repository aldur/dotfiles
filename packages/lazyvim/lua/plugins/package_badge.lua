-- Update the statusline to inform the user this is a light version.
local name = (require("nixCats").settings or {}).nixCats_packageName
if not name or name == "lazyvim" then
	return {}
end

-- A feather (nf-md-feather) for the light build; other non-default
-- packages spell their name out.
local badges = { ["lazyvim-light"] = "󰛓" }
name = badges[name] or name

return {
	{
		"nvim-lualine/lualine.nvim",
		opts = function(_, opts)
			opts.sections = opts.sections or {}
			opts.sections.lualine_x = opts.sections.lualine_x or {}
			-- In lualine_x with an accent highlight, like LazyVim's own
			-- indicators — not in the mode-colored z block with the clock.
			table.insert(opts.sections.lualine_x, 1, {
				function()
					return name
				end,
				color = "Special",
			})
		end,
	},
}
