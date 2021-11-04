local cmp = require 'cmp'

local check_back_space = function()
    local col = vim.fn.col('.') - 1
    return col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') ~= nil
end

cmp.register_source('note_tags', require'plugins/cmp_note_tags'.new())
cmp.register_source('notes', require'plugins/cmp_notes'.new())

-- Disabled as currently buggy.
cmp.register_source('note_headers', require'plugins/cmp_md_headers'.new())

local default_map_modes = {'i', 's', 'c'}

local function default_tab_mapping(fallback)
    if cmp.visible() then
        -- If completion menu is open, `tab` trigger completion of the
        -- selected item (or the first one if only one is open.)
        cmp.confirm({select = true})
    elseif check_back_space() then
        -- If it has backspace behind, fallback a literal tab.
        fallback()
    else
        -- Otherwise trigger completion.
        cmp.complete()
    end
end

cmp.setup({
    snippet = {expand = function(args) vim.fn["UltiSnips#Anon"](args.body) end},
    mapping = {
        ['<C-e>'] = cmp.mapping(function(fallback)
            -- First close the popup, then send `c-e`.
            if cmp.visible() then
                cmp.mapping.close()
            end
            fallback()
        end, default_map_modes),
        ['<Tab>'] = cmp.mapping({
            i = default_tab_mapping,
            s = default_tab_mapping,
            c = cmp.mapping.select_next_item(),
        })
    },
    sources = { -- Sorted by priority.
        -- markdown.wiki only
        {name = 'notes'}, -- Does not currently work well.
        {name = 'note_tags', max_item_count = 5}, {name = 'note_headers'},
        -- /markdown.wiki only
        {name = 'nvim_lsp'}, {name = 'nvim_lua'}, {name = 'ultisnips'}, {
            name = 'buffer',
            -- https://github.com/hrsh7th/cmp-buffer
            -- Source from visibile buffers.
            get_bufnrs = function()
                local bufs = {}
                for _, win in ipairs(vim.api.nvim_list_wins()) do
                    bufs[vim.api.nvim_win_get_buf(win)] = true
                end
                return vim.tbl_keys(bufs)
            end
        }, {name = 'path'}
    }
})

cmp.setup.cmdline(':', {
    sources = cmp.config.sources({{name = 'path'}}, {{name = 'cmdline'}})
})
cmp.setup.cmdline('/', {sources = {{name = 'buffer'}}})
