-- Original credits to https://github.com/tomaskallup/dotfiles/blob/master/nvim/lua/plugins/nvim-lspconfig.lua
local lspconfig = require 'lspconfig'
local util = require('lspconfig/util')

-- https://github.com/neovim/nvim-lspconfig/issues/500#issuecomment-876700701
local function get_python_path(workspace)
    local path = util.path

    -- Use activated virtualenv.
    if vim.env.VIRTUAL_ENV then
        return path.join(vim.env.VIRTUAL_ENV, 'bin', 'python')
    end

    -- Find and use virtualenv from pipenv in workspace directory.
    local match = vim.fn.glob(path.join(workspace, 'Pipfile'))
    if match ~= '' then
        local venv = vim.fn.trim(vim.fn.system(
                                     'PIPENV_PIPFILE=' .. match ..
                                         ' pipenv --venv'))
        local msg = "Activating Pipenv at " .. venv
        vim.cmd(([[echohl Function | echomsg "%s" | echohl None]]):format(vim.fn
                                                                              .escape(
                                                                              msg,
                                                                              "\"\\")))

        return path.join(venv, 'bin', 'python')
    end

    -- Fallback to system Python.
    return vim.fn.exepath('python3') or vim.fn.exepath('python') or 'python'
end

-- Setup everything on lsp attach
local on_attach = function(_, bufnr)
    require"lsp_signature".on_attach({
        bind = true, -- This is mandatory, otherwise border config won't get registered.
        handler_opts = {border = "single"}
    })

    -- Mappings
    local opts = {noremap = true, silent = true}

    local function buf_set_keymap(...)
        vim.api.nvim_buf_set_keymap(bufnr, ...)
    end

    -- Mnemonic for Usages
    buf_set_keymap('n', '<leader>u', '<cmd>lua vim.lsp.buf.references()<CR>',
                   opts)
    -- Mnemonic for Info
    buf_set_keymap('n', '<leader>i', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)

    buf_set_keymap('n', '<leader>f', '<cmd>lua vim.lsp.buf.formatting()<CR>',
                   opts)
    buf_set_keymap('n', '<c-]>', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)
end

-- Python pyright
lspconfig.pyright.setup {}
lspconfig.pyright.setup {
    on_attach = on_attach,
    on_init = function(client)
        client.config.settings.python.pythonPath =
            get_python_path(client.config.root_dir)
    end
}

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

-- https://www.chrisatmachine.com/Neovim/28-neovim-lua-development/
lspconfig.sumneko_lua.setup {
    cmd = {"/usr/local/bin/lua-langserver"},
    settings = {
        Lua = {
            runtime = {
                -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
                version = 'LuaJIT',
                -- Setup your lua path
                path = vim.split(package.path, ';')
            },
            diagnostics = {
                -- Get the language server to recognize the `vim` global
                globals = {'vim'}
            },
            workspace = {
                -- Make the server aware of Neovim runtime files
                library = {
                    [vim.fn.expand('$VIMRUNTIME/lua')] = true,
                    [vim.fn.expand('$VIMRUNTIME/lua/vim/lsp')] = true
                }
            },
            telemetry = {enable = false}
        }
    },
    on_attach = on_attach
}

-- https://github.com/golang/tools/blob/master/gopls/doc/vim.md#neovim-config
lspconfig.gopls.setup {on_attach = on_attach}

local function _read_buffer_variable(name, default, bufnr)
    local ok, result = pcall(vim.api.nvim_buf_get_var, bufnr, name)
    -- If not set, rely on the default value.
    if not ok then return default end

    return result
end

-- https://github.com/nvim-lua/diagnostic-nvim/issues/73
vim.lsp.handlers["textDocument/publishDiagnostics"] =
    vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
        -- disable virtual text
        virtual_text = function(bufnr, _)
            return _read_buffer_variable('show_virtual_text', true, bufnr)
        end,

        -- Use a function to dynamically turn signs off
        -- and on, using buffer local variables
        signs = function(bufnr, _)
            return _read_buffer_variable('show_signs', false, bufnr)
        end

        -- delay update diagnostics
        -- update_in_insert = false,
        -- display_diagnostic_autocmds = { "InsertLeave" },
    })
