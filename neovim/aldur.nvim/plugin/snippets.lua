local snippets = require('snippets')

local function snippets_path()
    for _, value in ipairs(vim.api.nvim_list_runtime_paths()) do
        if value:match("aldur%.nvim$") then return value .. "/snippets" end
    end
    print("Error: Could not find snippets path!")
    return nil
end

snippets.setup({
    friendly_snippets = false,
    search_paths = {snippets_path()},
    extended_filetypes = {['markdown.wiki'] = {"markdown", "wiki"}}
})

local map_opts = {expr = true, silent = true}

-- NOTE: `<Tab>` is configured through `nvim-cmp`.

vim.keymap.set({'i', 's'}, '<S-Tab>', function()
    if vim.snippet.active({direction = -1}) then
        vim.schedule(function() vim.snippet.jump(-1) end)
        return
    end
    return "<S-Tab>"
end, map_opts)

