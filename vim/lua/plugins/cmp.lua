local cmp = require 'cmp'

local check_back_space = function()
    local col = vim.fn.col('.') - 1
    return col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') ~= nil
end

cmp.register_source('note_tags', require'plugins/cmp_note_tags'.new())

cmp.setup({
    snippet = {expand = function(args) vim.fn["UltiSnips#Anon"](args.body) end},
    mapping = {
        ['<C-e>'] = cmp.mapping.close(),
        ['<Tab>'] = cmp.mapping(function(fallback)
            if vim.fn.pumvisible() == 1 then
                -- If completion menu is open, `tab` trigger completion of the
                -- selected item (or the first one if inly one is open.)
                cmp.confirm({select = true})
            elseif check_back_space() then
                -- If it has backspace behind, fallback a literal tab.
                fallback()
            else
                -- Otherwise trigger completion.
                cmp.complete()
            end
        end, {'i', 's'})
    },
    sources = { -- Sorted by priority.
        {name = 'note_tags'}, {name = 'nvim_lsp'}, {name = 'nvim_lua'},
        {name = 'ultisnips'}, {name = 'buffer'}, {name = 'path'}
    }
})
