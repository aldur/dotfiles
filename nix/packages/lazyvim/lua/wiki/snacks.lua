local M = {}

-- Get the configured force create key (default to <M-CR> if not set)
local function get_force_create_key()
  return vim.g.wiki_snacks_force_create_key or "<M-CR>"
end

---Open fuzzy finder for wiki pages
M.pages = function()
  local root = vim.g.wiki_root
  if not root then
    vim.notify("wiki_root is not set", vim.log.levels.ERROR)
    return
  end

  -- Expand tilde in wiki root path and ensure it ends with /
  root = vim.fn.expand(root)
  if root:sub(-1) ~= '/' then
    root = root .. '/'
  end

  -- Get all markdown files recursively in wiki root
  local items = vim.fn.globpath(root, "**/*.md", false, true)

  -- Convert to relative paths from wiki root
  local wiki_files = {}
  for _, file in ipairs(items) do
    -- Remove wiki root prefix to get relative path
    local wiki_relative = file:sub(#root + 1) -- +1 to skip the trailing slash

    table.insert(wiki_files, {
      file = file,  -- Absolute path for preview
      text = wiki_relative,
      wiki_relative = wiki_relative,
    })
  end

  require("snacks").picker.pick({
    prompt = "Wiki files> ",
    items = wiki_files,
    format = function(item)
      -- Show relative path but keep absolute path in item.file for preview
      return {
        { item.wiki_relative, "SnacksPickerFile", field = "file" }
      }
    end,
    confirm = function(picker, item)
      picker:close()
      local path
      if item then
        path = item.wiki_relative
      elseif picker.query and picker.query ~= "" then
        path = picker.query
      end

      if path then
        vim.fn["wiki#page#open"](path)
      end
    end,
    actions = {
      force_create = function(picker)
        -- Force create a new page with the current query
        if picker.query and picker.query ~= "" then
          vim.fn["wiki#page#open"](picker.query)
          picker:close()
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

---Open fuzzy finder for wiki tags
M.tags = function()
  local tags_with_locations = vim.fn["wiki#tags#get_all"]()
  local root = vim.fn["wiki#get_root"]()
  local items = {}

  for tag, locations in pairs(tags_with_locations) do
    for _, loc in pairs(locations) do
      local abs_path = loc[1]  -- Absolute path
      local rel_path = vim.fn["wiki#paths#relative"](abs_path, root)
      table.insert(items, {
        text = string.format("%s:%d:%s", tag, loc[2], rel_path),
        tag = tag,
        lnum = loc[2],
        file = abs_path,  -- Use absolute path for preview
        pos = { loc[2], 1 },  -- Line and column for preview
        rel_path = rel_path,  -- Relative path for opening
      })
    end
  end

  require("snacks").picker.pick({
    prompt = "Wiki tags> ",
    items = items,
    format = function(item)
      return {
        { item.tag, "Special" },
        { ":", "Comment" },
        { tostring(item.lnum), "Number" },
        { ":", "Comment" },
        { item.rel_path, "Directory" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.rel_path then
        vim.fn["wiki#page#open"](item.rel_path)
      end
    end,
  })
end

---Open fuzzy finder for table of contents
M.toc = function()
  local toc = vim.fn["wiki#toc#gather_entries"]()
  local items = {}

  for _, hd in pairs(toc) do
    local indent = string.rep(".", hd.level - 1)
    local line = indent .. hd.header
    table.insert(items, {
      text = string.format("%d:%s", hd.lnum, line),
      lnum = hd.lnum,
      header = hd.header,
      level = hd.level,
    })
  end

  -- Store current buffer info for preview
  local current_file = vim.api.nvim_buf_get_name(0)

  -- Add file info to items for preview
  for _, item in ipairs(items) do
    item.file = current_file
    item.pos = { item.lnum, 1 }
  end

  require("snacks").picker.pick({
    prompt = "TOC> ",
    items = items,
    format = "text",
    confirm = function(picker, item)
      picker:close()
      if item and item.lnum then
        vim.fn.execute(tostring(item.lnum))
      end
    end,
  })
end

---Select a wiki page and insert a link to it
---@param mode? "visual" | "insert"
M.links = function(mode)
  local text = ""
  if mode == "visual" then
    vim.cmd([[normal! "wd]])
    text = vim.fn.trim(vim.fn.getreg("w"))
  end

  local root = vim.g.wiki_root
  if not root then
    vim.notify("wiki_root is not set", vim.log.levels.ERROR)
    return
  end

  -- Expand tilde in wiki root path and ensure it ends with /
  root = vim.fn.expand(root)
  if root:sub(-1) ~= '/' then
    root = root .. '/'
  end

  -- Get all markdown files recursively in wiki root
  local items = vim.fn.globpath(root, "**/*.md", false, true)

  -- Convert to relative paths from wiki root
  local wiki_files = {}
  for _, file in ipairs(items) do
    -- Remove wiki root prefix to get relative path
    local wiki_relative = file:sub(#root + 1) -- +1 to skip the trailing slash

    table.insert(wiki_files, {
      file = file,  -- Absolute path for preview
      text = wiki_relative,
      wiki_relative = wiki_relative,
    })
  end

  require("snacks").picker.pick({
    prompt = "Add wiki link> ",
    items = wiki_files,
    format = function(item)
      -- Show relative path but keep absolute path in item.file for preview
      return {
        { item.wiki_relative, "SnacksPickerFile", field = "file" }
      }
    end,
    confirm = function(picker, item)
      picker:close()
      local note
      if item then
        note = item.file  -- Use absolute path for wiki#link#add
      elseif picker.query and picker.query ~= "" then
        -- If no selection but there's a query, use query as new page
        note = vim.fs.joinpath(vim.g.wiki_root, picker.query)
      end

      if note then
        vim.fn["wiki#link#add"](note, "", { text = text })
      end
    end,
    actions = {
      force_create = function(picker)
        -- Force create a link to a new page with the current query
        if picker.query and picker.query ~= "" then
          local note = vim.fs.joinpath(vim.g.wiki_root, picker.query)
          vim.fn["wiki#link#add"](note, "", { text = text })
          picker:close()
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

return M
