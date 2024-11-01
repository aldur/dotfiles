local cmp = require 'cmp'

-- https://github.com/onsails/lspkind-nvim/blob/master/lua/lspkind/init.lua
local kind_icons = {
    Text = "",
    Method = "",
    Function = "",
    Constructor = "",
    Field = "",
    Variable = "",
    Class = "ﴯ",
    Interface = "",
    Module = "",
    Property = "ﰠ",
    Unit = "",
    Value = "",
    Enum = "",
    Keyword = "",
    Snippet = "",
    Color = "",
    File = "",
    Reference = "",
    Folder = "",
    EnumMember = "",
    Constant = "",
    Struct = "",
    Event = "",
    Operator = "",
    TypeParameter = ""
}

local menu_identifiers = {
    buffer = "[Buf]",
    nvim_lsp = "[LSP]",
    ultisnips = "[Snips]",
    nvim_lua = "[Lua]",
    -- notes = "[Notes]",
    note_tags = "[NTags]",
    note_headers = "[NHead]",
    path = "[Path]",
    cmdline = "[Cmd]"
}

local check_back_space = function()
    local col = vim.fn.col('.') - 1
    return col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') ~= nil
end

-- Disabled as currently buggy.
-- cmp.register_source('notes', require'aldur.cmp.notes'.new())

cmp.register_source('note_tags', require'aldur.cmp.note_tags'.new())
cmp.register_source('note_headers', require'aldur.cmp.md_headers'.new())

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

local function format_if_nerdfont(vim_item)
    -- If there's a Nerd Font set, display fancy icons.
    if require('aldur.utils').is_nerdfont() then
        return kind_icons[vim_item.kind]
    end
    return vim_item.kind
end

local function is_buf_size_allowed(buf)
    local line_count = vim.api.nvim_buf_line_count(buf)
    local byte_size = vim.api.nvim_buf_get_offset(buf, line_count)
    return byte_size <= 1024 * 1024 -- 1 Megabyte max
end

-- https://github.com/hrsh7th/cmp-buffer
local function visible_buffers_only()
    local bufs = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        -- TODO: Ignore quickfix buffers and similar?
        -- Only show completions from visibile buffers.
        local buf = vim.api.nvim_win_get_buf(win)

        if is_buf_size_allowed(buf) then
            -- Discard buffers that are too big.
            bufs[buf] = true
        end
    end
    return vim.tbl_keys(bufs)
end

local function current_buffer_only()
    local buf = vim.api.nvim_get_current_buf()
    if is_buf_size_allowed(buf) then return {buf} end
    return {}
end

local current_buffer_source = {
    name = 'buffer',
    keyword_length = 3,
    option = {get_bufnrs = current_buffer_only}
}

local visible_buffers_source = {
    name = 'buffer',
    keyword_length = 3,
    option = {get_bufnrs = visible_buffers_only}
}

local default_sources = {
    -- Sorted by priority.
    {name = 'nvim_lsp'}, {name = 'ultisnips', keyword_length = 2},
    visible_buffers_source, {name = 'path'}
}

local md_sources = {
    -- {name = 'notes'}, -- Does not currently work well.
    {name = 'note_tags', max_item_count = 5}, {name = 'note_headers'}
}

-- Extend `md_sources` by appending the other sources.
for _, source in pairs(default_sources) do
    -- NOTE: You can't use `tbl_deep_extend` because it doesn't work on lists.
    -- NOTE: You can't use `list_extend` because we want to skip `buffer`.
    if source.name == 'buffer' then goto continue end
    table.insert(md_sources, source)
    ::continue::
end

cmp.setup.filetype({'markdown.wiki', 'markdown'}, {sources = md_sources})

-- NOTE: I am doing this as good practice, but the plugin is well-behaved and
-- disables itself on other buffers.
local vim_lua_sources = {{name = 'nvim_lua'}}
vim.list_extend(vim_lua_sources, default_sources)
cmp.setup.filetype({'lua', 'vim'}, {sources = vim_lua_sources})

local beancount_sources = {{name = 'beancount', max_item_count = 10}}
-- NOTE: Because `beancount` files are usually pretty big,
-- we are purposedly leaving out _other_ sources and just using its own.
-- vim.list_extend(beancount_sources, default_sources)
cmp.setup.filetype({'beancount'}, {sources = beancount_sources})

cmp.setup({
    formatting = {
        format = function(entry, vim_item)
            -- Kind icons
            vim_item.kind = format_if_nerdfont(vim_item)

            -- Source
            vim_item.menu = (menu_identifiers)[entry.source.name]
            return vim_item
        end
    },
    snippet = {expand = function(args) vim.fn["UltiSnips#Anon"](args.body) end},
    mapping = cmp.mapping.preset.insert({
        ['<C-e>'] = cmp.mapping(function(fallback)
            -- First close the popup, then send `c-e`.
            if cmp.visible() then cmp.mapping.close() end
            fallback()
        end, default_map_modes),
        ['<Tab>'] = cmp.mapping({
            i = default_tab_mapping,
            s = default_tab_mapping,
            c = cmp.mapping.select_next_item()
        })
    }),
    sources = default_sources,
    experimental = {ghost_text = true}
})

cmp.setup.cmdline(':', {
    sources = cmp.config.sources({
        -- Double brackets because this creates `group_index`es
        {name = 'path', max_item_count = 10}
    }, {
        -- Same here, another group
        {
            name = 'cmdline',
            -- https://github.com/hrsh7th/cmp-cmdline/issues/60
            -- `cmdline` completion works badly, and clashes w/ `path` completion
            -- Here we are manually disabling it for the commands we typically
            -- use which require a path.
            option = {ignore_cmds = {'Man', '!', 'edit'}},
            max_item_count = 10
        }
    }),
    mapping = cmp.mapping.preset.cmdline()
})

local search_config = {
    sources = {current_buffer_source},
    mapping = cmp.mapping.preset.cmdline()
}

cmp.setup.cmdline('/', search_config)
cmp.setup.cmdline('?', search_config)
