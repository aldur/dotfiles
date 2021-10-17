local cmp = require 'cmp'

local check_back_space = function()
    local col = vim.fn.col('.') - 1
    return col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') ~= nil
end

-- TODO: You were trying to display custom information, without success.
-- local function format(entry, vim_item)
--     local opts = {}
--     opts.menu = {
--       notes = "[Notes]",
--       note_tags = "[NoteTags]",
--     }

--     if opts.menu ~= nil then
--         vim_item.menu = opts.menu[entry.source.name]
--     end

--     if opts.maxwidth ~= nil then
--         vim_item.abbr = string.sub(vim_item.abbr, 1, opts.maxwidth)
--     end

--     return vim_item
-- end

cmp.register_source('note_tags', require'plugins/cmp_note_tags'.new())
cmp.register_source('notes', require'plugins/cmp_notes'.new())
cmp.register_source('note_headers', require'plugins/cmp_md_headers'.new())

cmp.setup({
    snippet = {expand = function(args) vim.fn["UltiSnips#Anon"](args.body) end},
    -- formatting = {format = format},
    mapping = {
        ['<C-e>'] = cmp.mapping.close(),
        ['<Tab>'] = cmp.mapping(function(fallback)
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
        end, {'i', 's'})
    },
    sources = { -- Sorted by priority.
        {name = 'notes'}, -- Does not currently work well.
        {name = 'note_tags', max_item_count = 5},
        {name = 'note_headers'},
        {name = 'nvim_lsp'},
        {name = 'nvim_lua'}, {name = 'ultisnips'}, {
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
