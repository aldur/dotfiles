-- Original credits to https://github.com/tomaskallup/dotfiles/blob/master/nvim/lua/plugins/nvim-lspconfig.lua
local lspconfig = require 'lspconfig'
-- -- Make sure this is a slash (as theres some metamagic happening behind the scenes)
-- local configs = require("lspconfig/configs")

-- Setup everything on lsp attach
local on_attach = function(client, bufnr)
    -- Enable auto-complete.
    require'completion'.on_attach()

    -- Mappings
    local opts = {noremap = true, silent = true}

    local function buf_set_keymap(...)
        vim.api.nvim_buf_set_keymap(bufnr, ...)
    end

    -- Mnemonic for usages
    buf_set_keymap('n', '<leader>u', '<cmd>lua vim.lsp.buf.references()<CR>',
                   opts)
    -- Mnemonic for info
    buf_set_keymap('n', '<leader>i', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)

    buf_set_keymap('n', '<leader>f', '<cmd>lua vim.lsp.buf.formatting()<CR>',
                   opts)
    buf_set_keymap('n', '<c-]>', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)
end

-- Python pyright
lspconfig.pyright.setup {on_attach = on_attach}

-- Vim lsp
lspconfig.vimls.setup {on_attach = on_attach}

-- Formatting/linting via efm
local prettier = require "efm/prettier"

local efm_languages = {
    markdown = {require 'efm/mdl', prettier},
    lua = {require 'efm/luafmt', require 'efm/luacheck'},
    python = {require 'efm/black'},
    vim = {require 'efm/vint'},
    sh = {require 'efm/shellcheck', require 'efm/shfmt'},
    bib = {require 'efm/bibtool'},
    cpp = {require 'efm/astyle'},
    json = {require 'efm/jq'}
}
efm_languages['markdown.wiki'] = efm_languages['markdown']
efm_languages['sh.env'] = efm_languages['sh']
table.insert(efm_languages['sh.env'], require 'efm/dotenv')
efm_languages['c'] = efm_languages['cpp']

lspconfig.efm.setup {
    filetypes = vim.tbl_keys(efm_languages),
    init_options = {documentFormatting = true, codeAction = true},
    settings = {
        languages = efm_languages
        -- log_level = 1,
        -- log_file = '~/efm.log',
    },
    on_attach = on_attach
}

vim.lsp.handlers["textDocument/publishDiagnostics"] =
    vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
        -- disable virtual text
        -- virtual_text = false,

        -- show signs
        signs = false

        -- delay update diagnostics
        -- update_in_insert = false,
        -- display_diagnostic_autocmds = { "InsertLeave" },
    })
