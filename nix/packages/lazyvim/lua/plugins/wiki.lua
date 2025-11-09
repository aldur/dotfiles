local function template(context)
	local author = "Adriano Di Luzio"

	vim.fn.append(0, "---")
	vim.fn.append(1, "author: " .. author)
	vim.fn.append(2, "date: " .. context.date .. " " .. context.time)
	vim.fn.append(3, "tags:")
	vim.fn.append(4, "---")
	vim.fn.append(5, "")
	vim.fn.append(6, "# " .. context.name)
end

local function match(_)
	return true
end

return {
	{
		"lervag/wiki.vim",
		init = function()
			vim.g.wiki_root = "~/Documents/Notes/"

			local assets_root = vim.env.LAZYVIM_MD2HTML_ASSETS
			local pandoc_args = {}
			if assets_root then
				pandoc_args = {
					"--embed-resources",
					"--standalone",
					"--lua-filter " .. assets_root .. "/header_as_title.lua",
					"--lua-filter " .. assets_root .. "/todo_to_checkbox.lua",
					"--lua-filter " .. assets_root .. "/colored_markers.lua",
					"--template GitHub.html5",
					"--data-dir " .. assets_root,
				}
			end

			vim.g.wiki_export = {
				from_format = "markdown",
				ext = "html",
				view = true,
				link_ext_replace = true,
				args = vim.iter(pandoc_args):join(" "),
			}

			vim.g.wiki_templates = {
				{ match_func = match, source_func = template },
			}

			vim.g.wiki_link_creation = {
				md = { link_type = "md", url_extension = "" },
			}

			-- Use snacks for UI selection
			vim.g.wiki_select_method = {
				pages = require("wiki.snacks").pages,
				tags = require("wiki.snacks").tags,
				toc = require("wiki.snacks").toc,
				links = require("wiki.snacks").links,
			}

			-- Equivalent to g:wiki_fzf_force_create_key
			vim.g.wiki_snacks_force_create_key = "<C-x>"
		end,
		config = function()
			-- Create command for searching wiki content
			vim.api.nvim_create_user_command("WikiGrep", function()
				require("wiki.snacks").grep()
			end, { desc = "Search wiki content (live)" })

			-- Add convenient keymap (using ws for "wiki search")
			vim.keymap.set("n", "<leader>ws", "<cmd>WikiGrep<cr>", { desc = "Search wiki content" })
		end,
	},
}
