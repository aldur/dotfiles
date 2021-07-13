local compe = require('compe')
compe.setup {
    enabled = true,
    autocomplete = true,
    documentation = true,

    source = {
        path = true,
        buffer = true,
        tags = false,
        spell = false,
        calc = true,
        omni = false,
        emoji = false,

        nvim_lsp = true,
        nvim_lua = true,

        vsnip = false,
        ultisnips = true,
        luasnip = false,

        -- markdown.wiki only
        notes = true,
        note_tags = true
    }
}

compe.register_source('note_tags', require 'plugins/compe_note_tags')
compe.register_source('notes', require 'plugins/compe_notes')

local t = function(str)
    return vim.api.nvim_replace_termcodes(str, true, true, true)
end

local check_back_space = function()
    local col = vim.fn.col('.') - 1
    return col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') ~= nil
end

-- Trigger completion if the menu is closed,
-- otherwise accept suggestion.
_G.tab_complete = function()
    if vim.fn.pumvisible() == 1 then
        return vim.fn['compe#confirm']({select = true})
    elseif check_back_space() then
        return t "<Tab>"
    else
        return vim.fn['compe#complete']()
    end
end

local complete_s = "v:lua.tab_complete()"
for _, m in ipairs({"i", "s"}) do
    vim.api.nvim_set_keymap(m, "<Tab>", complete_s, {expr = true})
end
