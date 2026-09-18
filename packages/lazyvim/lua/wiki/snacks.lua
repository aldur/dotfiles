local M = {}

-- Preserve letters (including Unicode), digits, and identifier punctuation.
-- Other punctuation is a separator, never a path, anchor, or URL scheme.
function M.slug(title)
	title = title:gsub("%+", "-plus-"):gsub("(%w)#(%s)", "%1-sharp%2"):gsub("(%w)#$", "%1-sharp")
	local chars = vim.fn.split(vim.fn.tolower(vim.trim(title)), [[\zs]])
	for i, char in ipairs(chars) do
		local keep = char:match("^[%w_.-]$") or (char:byte() >= 128 and vim.fn.charclass(char) >= 2)
		if not keep then
			chars[i] = "-"
		end
	end
	local slug = table.concat(chars)
	slug = slug:gsub("%-+", "-"):gsub("^[._-]+", ""):gsub("[._-]+$", "")
	if slug == "" then
		return nil
	end
	return slug
end

local function escape_label(text)
	-- Entities keep labels readable in Markdown and parseable by wiki.vim,
	-- whose link recognizer does not support escaped brackets in labels.
	return (text:gsub("&", "&amp;"):gsub("\\", "&#92;"):gsub("%[", "&#91;"):gsub("%]", "&#93;"))
end

-- Make a relative Markdown URL without changing the actual filename.
function M.link_path(path)
	path = vim.fn["wiki#paths#relative"](path, vim.fn.expand("%:p:h"))
	return (
		path:gsub(".", function(char)
			if char:byte() < 128 and not char:match("[%w/_.~-]") then
				return string.format("%%%02X", char:byte())
			end
			return char
		end)
	)
end

local function open_page(path)
	vim.fn["wiki#url#follow"]("md:" .. M.link_path(path))
end

-- Keep existing filenames usable, including notes created before this convention.
-- Only the final component is a title; directory paths are always literal.
local function normalize_name(name, base)
	name = vim.trim(name)
	local path = name
	local bases = base and { base } or { vim.fn.expand("%:p:h"), vim.g.wiki_root or vim.fn.getcwd() }
	for _, base in ipairs(bases) do
		local candidate = path:sub(1, 1) == "/" and path or vim.fs.joinpath(base, path)
		if vim.fn.filereadable(candidate) == 1 or vim.fn.filereadable(candidate .. ".md") == 1 then
			return name
		end
	end
	local parent, title = path:match("^(.-)([^/]*)$")
	local extension = title:match("%.[mM][dD]$") and ".md" or ""
	if extension ~= "" then
		title = title:sub(1, -4)
	end
	title = M.slug(title)
	return title and parent .. title .. extension or nil
end

function M.normalize_url(name)
	-- Explicit URLs and TOC entries may contain real anchors.
	local path, anchor = name:match("^([^#]*)(.*)$")
	path = path == "" and "" or normalize_name(path)
	return vim.fn["wiki#url#utils#url_encode_specific"]((path or "") .. anchor, "()")
end

function M.page_name(input, root)
	local name = normalize_name(input, root)
	if not name then
		return nil
	end
	if not name:match("%.md$") then
		name = name .. ".md"
	end
	return name
end

local function page_title(input)
	local title = vim.trim(input):match("([^/]+)$") or ""
	return (title:gsub("%.[mM][dD]$", ""))
end

local function get_force_create_key()
	return vim.g.wiki_snacks_force_create_key or "<M-CR>"
end

function M.title_link(text)
	if vim.fn["wiki#link#get_creator"]("link_type") ~= "md" then
		return vim.fn["wiki#link#templates#word"](text)
	end
	local slug = M.slug((text:gsub("%.[mM][dD]$", "")))
	if not slug then
		vim.notify("Page title needs at least one letter or digit", vim.log.levels.WARN)
		return ""
	end
	local wiki = vim.b.wiki or {}
	local root = vim.fn.expand("%:p:h")
	if wiki.in_journal == 1 or wiki.in_journal == true then
		root = wiki.root
	end
	local path = vim.fs.joinpath(root, slug .. ".md")
	return "[" .. escape_label(text) .. "](" .. M.link_path(path) .. ")"
end

local function create_page(picker, root, on_ready)
	local input = vim.trim(picker.input:get())
	if input == "" then
		return
	end
	local name = M.page_name(input, root)
	if not name then
		vim.notify("Page title needs at least one letter or digit", vim.log.levels.WARN)
		return
	end
	picker:close()
	-- Restore the source window before opening the page or inserting its link.
	vim.schedule(function()
		on_ready(vim.fs.joinpath(root, name), input)
	end)
end

local function wiki_root()
	local root = vim.g.wiki_root
	if not root or root == "" then
		vim.notify("wiki_root is not set", vim.log.levels.ERROR)
		return
	end
	return vim.fn.expand(root):gsub("/+$", "") .. "/"
end

local function wiki_files(root)
	local items = {}
	for _, file in ipairs(vim.fn.globpath(root, "**/*.md", false, true)) do
		table.insert(items, { file = file, text = file:sub(#root + 1) })
	end
	return items
end

function M.pages()
	local root = wiki_root()
	if not root then
		return
	end
	local function create(picker)
		create_page(picker, root, open_page)
	end

	require("snacks").picker.pick({
		prompt = "Wiki files> ",
		items = wiki_files(root),
		actions = {
			confirm = function(picker, item)
				if item then
					picker:close()
					open_page(vim.fs.joinpath(root, item.text))
				else
					create(picker)
				end
			end,
			force_create = create,
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

function M.tags()
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
					open_page(vim.fs.joinpath(root, item.path))
				end
			end,
		},
	})
end

function M.toc()
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

local function toggle_fuzzy(picker)
	local fuzzy = not picker.matcher.opts.fuzzy
	picker.opts.matcher.fuzzy = fuzzy
	picker.matcher.opts.fuzzy = fuzzy
	-- Reparse the current query and reconsider previously excluded files.
	picker.matcher:init("")
	picker.title = "Wiki links: paths + contents [" .. (fuzzy and "fuzzy" or "literal") .. "]"
	picker:find()
end

local function search_help(picker)
	vim.cmd.stopinsert()
	require("snacks").win({
		title = " Wiki link search ",
		zindex = require("snacks").win.zindex({ max = math.huge }) + 1,
		text = {
			"Searches paths, body text, and YAML frontmatter.",
			"Saved files use unsaved buffer edits when available.",
			"Alt-z toggles fuzzy; each picker starts literal.",
			"Fuzzy allows gaps: wgt matches widget.",
			"",
			"widget       Literal substring, not scattered letters.",
			"blue widget  Both terms required, anywhere in the file.",
			"widget       Lowercase ignores case.",
			"Widget       Uppercase makes that term case-sensitive.",
			"",
			"One result per file. Enter inserts its page link.",
			"The label uses selected text, otherwise the page title.",
			get_force_create_key() .. " creates a page from the query; Enter also does this",
			"when there are no matches. Existing pages are reused.",
		},
		width = 62,
		height = 14,
		border = "rounded",
		footer = " Esc / q: back to search ",
		enter = true,
		keys = { q = "close", ["<Esc>"] = "close" },
		on_close = function()
			if not picker.closed then
				picker:focus()
			end
		end,
	})
end

---@param mode? "visual" | "insert"
function M.links(mode)
	-- Keep the selection intact until a page is chosen; cancelling must not cut it.
	local link_mode = mode == "visual" and "visual" or ""
	local selection
	if link_mode == "visual" then
		if vim.fn.getpos("'<")[2] ~= vim.fn.getpos("'>")[2] or vim.fn.visualmode() ~= "v" then
			vim.notify("Select text on a single line to add a wiki link", vim.log.levels.WARN)
			return
		end
		local lines = vim.fn.getregion(vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = vim.fn.visualmode() })
		selection = escape_label(vim.trim(table.concat(lines, "\n")))
	end

	local root = wiki_root()
	if not root then
		return
	end
	local items = wiki_files(root)

	local function create_link(picker)
		create_page(picker, root, function(path, input)
			local options = { text = selection or escape_label(page_title(input)) }
			vim.fn["wiki#link#add"](path, link_mode, options)
		end)
	end

	-- Match on the full note, but render one filename per result. Prefer loaded
	-- buffers so a query can find edits that have not been saved yet.
	for _, item in ipairs(items) do
		local buf = vim.fn.bufnr(item.file)
		local ok, lines
		if buf >= 0 and vim.api.nvim_buf_is_loaded(buf) then
			ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
			item.buf = buf
		else
			ok, lines = pcall(vim.fn.readfile, item.file)
		end
		if ok then
			item.text = item.text .. " " .. table.concat(lines, " ")
		end
	end

	require("snacks").picker.pick({
		prompt = "Add wiki link> ",
		title = "Wiki links: paths + contents [literal]",
		cwd = root,
		format = "file",
		matcher = { fuzzy = false },
		items = items,
		actions = {
			toggle_fuzzy = toggle_fuzzy,
			search_help = search_help,
			confirm = function(picker, item)
				if item then
					picker:close()
					vim.fn["wiki#link#add"](
						item.file,
						link_mode,
						{ text = selection or escape_label(vim.fn["wiki#toc#get_page_title"](item.file)) }
					)
				else
					create_link(picker)
				end
			end,
			force_create = create_link,
		},
		win = {
			input = {
				footer = " Alt-z: literal/fuzzy · Alt-s: help ",
				footer_pos = "left",
				keys = {
					["<a-s>"] = { "search_help", mode = { "i", "n" }, desc = "Wiki search rules" },
					["<a-z>"] = { "toggle_fuzzy", mode = { "i", "n" }, desc = "Toggle fuzzy matching" },
					[get_force_create_key()] = { "force_create", mode = { "i", "n" } },
				},
			},
		},
	})
end

function M.grep()
	local root = wiki_root()
	if not root then
		return
	end

	require("snacks").picker.grep({
		prompt = "Search wiki> ",
		cwd = root,
		query = "",
		live = true,
	})
end

return M
