local M = {}

-- Get the configured force create key (default to <M-CR> like wiki.vim)
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
  if root:sub(-1) ~= "/" then
    root = root .. "/"
  end

  -- Get all markdown files recursively in wiki root
  local files = vim.fn.globpath(root, "**/*.md", false, true)

  -- Convert to relative paths from wiki root
  local items = {}
  for _, file in ipairs(files) do
    local relative = file:sub(#root + 1)
    table.insert(items, {
      file = file,  -- For preview
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
          -- No selection - use the query to create a new page
          local input = picker.input and picker.input:get()
          if not input or input == "" then
            -- Fallback: try to get text from the input buffer
            if picker.input and picker.input.win and picker.input.win:valid() then
              input = picker.input.win:line()
            end
          end

          if input and input ~= "" then
            note = input
            -- Add .md extension if not present
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
        -- Force create a new page with the current input
        local input = picker.input and picker.input:get()
        if not input or input == "" then
          if picker.input and picker.input.win and picker.input.win:valid() then
            input = picker.input.win:line()
          end
        end

        if input and input ~= "" then
          local note = input
          -- Add .md extension if not present
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

---Open fuzzy finder for wiki tags
M.tags = function()
  local tags_with_locations = vim.fn["wiki#tags#get_all"]()
  local root = vim.fn["wiki#get_root"]()
  local items = {}

  for tag, locations in pairs(tags_with_locations) do
    for _, loc in pairs(locations) do
      local path = vim.fn["wiki#paths#relative"](loc[1], root)
      table.insert(items, {
        text = string.format("%s:%d:%s", tag, loc[2], path),
        file = loc[1],  -- For preview
        pos = { loc[2], 1 },  -- For preview position
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

---Open fuzzy finder for table of contents
M.toc = function()
  local toc = vim.fn["wiki#toc#gather_entries"]()
  local items = {}
  local current_file = vim.api.nvim_buf_get_name(0)

  for _, hd in pairs(toc) do
    local indent = string.rep(".", hd.level - 1)
    local line = indent .. hd.header
    table.insert(items, {
      text = string.format("%d:%s", hd.lnum, line),
      file = current_file,  -- For preview
      pos = { hd.lnum, 1 },  -- For preview position
      lnum = hd.lnum,
    })
  end

  require("snacks").picker.pick({
    prompt = "TOC> ",
    items = items,
    format = "text",
    actions = {
      confirm = function(picker, item)
        picker:close()
        if item and item.lnum then
          vim.fn.execute(tostring(item.lnum))
        end
      end,
    },
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
  if root:sub(-1) ~= "/" then
    root = root .. "/"
  end

  -- Get all markdown files recursively in wiki root
  local files = vim.fn.globpath(root, "**/*.md", false, true)

  -- Convert to relative paths from wiki root
  local items = {}
  for _, file in ipairs(files) do
    local relative = file:sub(#root + 1)
    table.insert(items, {
      file = file,  -- For preview and for wiki#link#add
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
          note = item.file  -- Use absolute path
        else
          -- No selection - use the query to create a new link
          local input = picker.input and picker.input:get()
          if not input or input == "" then
            -- Fallback: try to get text from the input buffer
            if picker.input and picker.input.win and picker.input.win:valid() then
              input = picker.input.win:line()
            end
          end

          if input and input ~= "" then
            note = input
            -- Add .md extension if not present
            if not note:match("%.md$") then
              note = note .. ".md"
            end
            note = vim.fs.joinpath(root, note)
          end
        end

        if note and note ~= "" then
          vim.fn["wiki#link#add"](note, "", { text = text })
        end
      end,
      force_create = function(picker)
        -- Force create a link to a new page with the current input
        local input = picker.input and picker.input:get()
        if not input or input == "" then
          if picker.input and picker.input.win and picker.input.win:valid() then
            input = picker.input.win:line()
          end
        end

        if input and input ~= "" then
          local note = input
          -- Add .md extension if not present
          if not note:match("%.md$") then
            note = note .. ".md"
          end
          note = vim.fs.joinpath(root, note)
          picker:close()
          vim.fn["wiki#link#add"](note, "", { text = text })
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