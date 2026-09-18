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
	-- `g:wiki_global_load` starts wiki.vim on every markdown buffer, also
	-- outside of the wiki. wiki.vim sets `b:wiki.root` only for the buffers
	-- inside the wiki. Add the template to those buffers only.
	local wiki = vim.b.wiki
	return wiki ~= nil and wiki.root ~= nil
end

local function startup_wiki_root()
	-- Match wiki.vim's outermost-index convention: section indexes such as
	-- section/index.md belong to the notebook containing them.
	local root
	local directory = vim.fn.getcwd()
	while directory do
		if vim.fn.filereadable(vim.fs.joinpath(directory, "index.md")) == 1 then
			root = directory
		end
		local parent = vim.fs.dirname(directory)
		directory = parent ~= directory and parent or nil
	end
	return root
end

return {
	{
		"lervag/wiki.vim",
		init = function()
			-- Set the root only when the directory exists: wiki.vim warns
			-- about a missing root at every start. A host without a wiki
			-- (containers, the light build) stays quiet; the pickers report
			-- the unset root when a wiki command runs.
			local override = vim.env.WIKI_ROOT
			override = override and override ~= "" and override or nil
			local default = vim.fn.expand("~/Documents/Notes")
			local detected = not override and startup_wiki_root() or nil
			local root = vim.fn.expand(override or detected or default)
			if vim.fn.isdirectory(root) == 1 then
				root = vim.uv.fs_realpath(root) or vim.fn.fnamemodify(root, ":p")
				vim.g.wiki_root = root
				if detected and root ~= (vim.uv.fs_realpath(default) or default) then
					vim.schedule(function()
						vim.notify("Auto-detected wiki root: " .. root, vim.log.levels.INFO, { title = "Wiki" })
					end)
				end
			end

			-- The assets and pandoc both ride the `markdown` category, so the light
			-- build has neither. Configure the export only when pandoc can run it.
			-- An export configuration without pandoc fails at use, not at start.
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

			if vim.fn.executable("pandoc") == 1 then
				vim.g.wiki_export = {
					from_format = "markdown",
					ext = "html",
					view = true,
					link_ext_replace = true,
					args = vim.iter(pandoc_args):join(" "),
				}
			end

			vim.g.wiki_templates = {
				{ match_func = match, source_func = template },
			}

			vim.g.wiki_link_creation = {
				md = { link_type = "md", url_extension = ".md" },
			}
			-- Vimscript calls this as a Funcref; Lua functions cannot be stored in vim.g.
			vim.cmd(
				[[let g:wiki_link_creation.md.url_transform = {name -> luaeval("require('wiki.snacks').normalize_url(_A)", name)}]]
			)
			vim.cmd(
				[[let g:wiki_link_creation.md.path_transform = {path -> luaeval("require('wiki.snacks').link_path(_A)", path)}]]
			)

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
			-- Plain text is a title; page-opening and TOC URLs use a separate hook.
			vim.cmd([[
function! WikiNotebookTitleLink(text, ...) abort
  return luaeval("require('wiki.snacks').title_link(_A)", a:text)
endfunction
call extend(g:wiki#link#definitions#word, {'__transformer': function('WikiNotebookTitleLink')})
]])
			-- Create command for searching wiki content
			vim.api.nvim_create_user_command("WikiGrep", function()
				require("wiki.snacks").grep()
			end, { desc = "Search wiki content (live)" })

			-- Add convenient keymap (using ws for "wiki search")
			vim.keymap.set("n", "<leader>wss", "<cmd>WikiGrep<cr>", { desc = "Search wiki content" })
		end,
	},
}
