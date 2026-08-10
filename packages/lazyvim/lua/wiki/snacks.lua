local M = {}

local function get_force_create_key()
	return vim.g.wiki_snacks_force_create_key or "<M-CR>"
end

-- `input:get()` reads the prompt window's line. Reading it after
-- `picker:close()` works: the close only schedules the teardown, so the
-- window is still there while a confirm action runs.
local function get_picker_input(picker)
	return picker.input and picker.input:get()
end

M.pages = function()
	local root = vim.g.wiki_root
	-- wiki.vim turns an unset root into "": both mean "no wiki here".
	if not root or root == "" then
		vim.notify("wiki_root is not set", vim.log.levels.ERROR)
		return
	end

	root = vim.fn.expand(root)
	if root:sub(-1) ~= "/" then
		root = root .. "/"
	end

	local files = vim.fn.globpath(root, "**/*.md", false, true)
	local items = {}
	for _, file in ipairs(files) do
		local relative = file:sub(#root + 1)
		table.insert(items, {
			file = file,
			text = relative,
		})
	end

	require("snacks").picker.pick({
		prompt = "Wiki files> ",
		items = items,
		actions = {
			confirm = function(picker, item)
				picker:close()

				local note
				if item then
					note = item.text
				else
					local input = get_picker_input(picker)
					if input and input ~= "" then
						note = input
						if not note:match("%.md$") then
							note = note .. ".md"
						end
					end
				end

				if note and note ~= "" then
					vim.fn["wiki#page#open"](note)
				end
			end,
			force_create = function(picker)
				local input = get_picker_input(picker)
				if input and input ~= "" then
					local note = input
					if not note:match("%.md$") then
						note = note .. ".md"
					end
					picker:close()
					vim.fn["wiki#page#open"](note)
				end
			end,
		},
		win = {
			input = {
				keys = {
					[get_force_create_key()] = { "force_create", mode = { "i", "n" } },
				},
			},
		},
	})
end

M.tags = function()
	local tags_with_locations = vim.fn["wiki#tags#get_all"]()
	local root = vim.fn["wiki#get_root"]()
	local items = {}

	for tag, locations in pairs(tags_with_locations) do
		for _, loc in pairs(locations) do
			local path = vim.fn["wiki#paths#relative"](loc[1], root)
			table.insert(items, {
				text = string.format("%s:%d:%s", tag, loc[2], path),
				file = loc[1], -- For preview
				pos = { loc[2], 1 }, -- For preview position
				tag = tag,
				lnum = loc[2],
				path = path,
			})
		end
	end

	require("snacks").picker.pick({
		prompt = "Wiki tags> ",
		items = items,
		format = "text",
		actions = {
			confirm = function(picker, item)
				picker:close()
				if item and item.path then
					vim.fn["wiki#page#open"](item.path)
				end
			end,
		},
	})
end

M.toc = function()
	local toc = vim.fn["wiki#toc#gather_entries"]()
	local items = {}
	local current_file = vim.api.nvim_buf_get_name(0)

	for _, hd in pairs(toc) do
		local indent = string.rep(".", hd.level - 1)
		local line = indent .. hd.header
		table.insert(items, {
			text = string.format("%d:%s", hd.lnum, line),
			file = current_file,
			pos = { hd.lnum, 1 },
		})
	end

	require("snacks").picker.pick({
		prompt = "TOC> ",
		items = items,
	})
end

---@param mode? "visual" | "insert"
M.links = function(mode)
	-- Do not cut the selection here. `wiki#link#add` does it itself for the
	-- "visual" mode, after the user selects a page. This function opens an
	-- asynchronous picker, so a cut here is lost if the user cancels the picker.
	-- The `xnoremap` that calls this leaves visual mode first, and `wiki#link#add`
	-- uses `gv`, so the selection is still available in the action below.
	local link_mode = mode == "visual" and "visual" or ""

	local root = vim.g.wiki_root
	-- wiki.vim turns an unset root into "": both mean "no wiki here".
	if not root or root == "" then
		vim.notify("wiki_root is not set", vim.log.levels.ERROR)
		return
	end

	root = vim.fn.expand(root)
	if root:sub(-1) ~= "/" then
		root = root .. "/"
	end

	local files = vim.fn.globpath(root, "**/*.md", false, true)
	local items = {}
	for _, file in ipairs(files) do
		local relative = file:sub(#root + 1)
		table.insert(items, {
			file = file,
			text = relative,
		})
	end

	require("snacks").picker.pick({
		prompt = "Add wiki link> ",
		items = items,
		actions = {
			confirm = function(picker, item)
				picker:close()

				local note
				if item then
					note = item.file -- Use absolute path
				else
					local input = get_picker_input(picker)
					if input and input ~= "" then
						note = input
						if not note:match("%.md$") then
							note = note .. ".md"
						end
						note = vim.fs.joinpath(root, note)
					end
				end

				if note and note ~= "" then
					vim.fn["wiki#link#add"](note, link_mode)
				end
			end,
			force_create = function(picker)
				local input = get_picker_input(picker)
				if input and input ~= "" then
					local note = input
					if not note:match("%.md$") then
						note = note .. ".md"
					end
					note = vim.fs.joinpath(root, note)
					picker:close()
					vim.fn["wiki#link#add"](note, link_mode)
				end
			end,
		},
		win = {
			input = {
				keys = {
					[get_force_create_key()] = { "force_create", mode = { "i", "n" } },
				},
			},
		},
	})
end

M.grep = function()
	local root = vim.g.wiki_root
	-- wiki.vim turns an unset root into "": both mean "no wiki here".
	if not root or root == "" then
		vim.notify("wiki_root is not set", vim.log.levels.ERROR)
		return
	end

	root = vim.fn.expand(root)

	require("snacks").picker.grep({
		prompt = "Search wiki> ",
		cwd = root,
		query = "",
		live = true,
	})
end

return M
