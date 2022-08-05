-- Original credits to https://github.com/tomaskallup/dotfiles/blob/master/nvim/lua/plugins/nvim-lspconfig.lua
local lspconfig = require 'lspconfig'
local util = require('lspconfig/util')
local M = {}

local function get_venv(workspace)
    -- Use activated virtualenv.
    if vim.env.VIRTUAL_ENV then return vim.env.VIRTUAL_ENV end

    -- Find and use virtualenv from pipenv in workspace directory.
    local match = vim.fn.glob(util.path.join(workspace, 'Pipfile'))
    if match ~= '' then
        local venv = vim.fn.trim(vim.fn.system(
                                     'PIPENV_PIPFILE=' .. match ..
                                         ' pipenv --venv'))

        local msg = "Activating Pipenv at " .. venv
        _G.info_message(msg)

        return venv
    end

    return nil
end

-- https://github.com/neovim/nvim-lspconfig/issues/500#issuecomment-876700701
local function get_python_path(workspace)
    local venv = get_venv(workspace)
    if venv then return util.path.join(venv, 'bin', 'python') end

    -- Fallback to system Python.
    return vim.fn.exepath('python3') or vim.fn.exepath('python') or 'python'
end

local capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp
                                                                     .protocol
                                                                     .make_client_capabilities())

-- Setup everything on lsp attach
local default_on_attach = function(client, bufnr)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

    require"lsp_signature".on_attach({
        bind = true, -- This is mandatory, otherwise border config won't get registered.
        handler_opts = {border = "single"}
    })

    -- Mappings
    local opts = {noremap = true, silent = true}

    local function buf_set_keymap(...)
        vim.api.nvim_buf_set_keymap(bufnr, ...)
    end

    if client.resolved_capabilities.find_references then
        -- Mnemonic for Usages
        buf_set_keymap('n', '<leader>u',
                       '<cmd>lua vim.lsp.buf.references()<CR>', opts)
    end

    -- Mnemonic for Info
    buf_set_keymap('n', '<leader>i', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)
    buf_set_keymap('n', '<leader>c', '<cmd>lua vim.lsp.buf.code_action()<CR>',
                   opts)
    buf_set_keymap('x', '<leader>c',
                   '<esc><cmd>lua vim.lsp.buf.range_code_action()<CR>', opts)

    buf_set_keymap('n', '<leader>f', '<cmd>lua vim.lsp.buf.formatting()<CR>',
                   opts)
    buf_set_keymap('n', '<c-]>', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)
    -- buf_set_keymap('n', '<leader>lo', '<cmd>TroubleToggle loclist<CR>', opts)
end

local default_lsp_config = {
    on_attach = default_on_attach,
    capabilities = capabilities,
    flags = {debounce_text_changes = 200}
}

local function extend_config(tbl)
    return vim.tbl_deep_extend('force', default_lsp_config, tbl)
end

-- Python pyright
lspconfig.pyright.setup(extend_config({
    on_init = function(client)
        client.config.settings.python.pythonPath =
            get_python_path(client.config.root_dir)
    end
}))

-- Inspired by:
-- https://github.com/python-lsp/python-lsp-server/pull/68
local function pylsp_cmd_env(workspace)
    local venv = get_venv(workspace)
    if venv then
        return {
            VIRTUAL_ENV = venv,
            PATH = util.path.join(venv, 'bin') .. ':' .. vim.env.PATH
        }
    end

    return {}
end

-- https://github.com/python-lsp/python-lsp-server
lspconfig.pylsp.setup(extend_config({
    on_attach = function(client, bufnr)
        -- Disable all non-required features as we also use Black/efm/pyright.
        client.resolved_capabilities.document_formatting = false
        client.resolved_capabilities.completion = false
        client.resolved_capabilities.document_highlight = false
        client.resolved_capabilities.document_range_formatting = false
        client.resolved_capabilities.find_references = false
        client.resolved_capabilities.goto_definition = false
        client.resolved_capabilities.execute_command = true
        client.resolved_capabilities.document_symbol = false
        client.resolved_capabilities.hover = false
        client.resolved_capabilities.rename = false
        client.resolved_capabilities.signature_help = false
        client.resolved_capabilities.code_lens = false
        client.resolved_capabilities.code_action = true
        default_on_attach(client, bufnr)
    end,
    on_new_config = function(new_config, new_root_dir)
        new_config['cmd_env'] = pylsp_cmd_env(new_root_dir)
    end
}))

-- Vim lsp
lspconfig.vimls.setup(extend_config({flags = {debounce_text_changes = 500}}))

-- Formatting/linting via efm
local efm_languages = {
    markdown = {require 'efm/mdl', require 'efm/prettier_markdown'},
    lua = {require 'efm/luafmt', require 'efm/luacheck'},
    python = {require 'efm/black'},
    dockerfile = {require 'efm/hadolint'},
    vim = {require 'efm/vint'},
    sh = {require 'efm/shellcheck', require 'efm/shfmt'},
    bib = {require 'efm/bibtool'},
    cpp = {require 'efm/astyle'},
    json = {require 'efm/jq'},
    xml = {require 'efm/xmltidy'},
    solidity = {require 'efm/prettier_solidity', require 'efm/solhint'},
    typescript = {require 'efm/prettier_typescript'},
    javascript = {require 'efm/prettier_javascript'}
}
efm_languages['markdown.wiki'] = efm_languages['markdown']
efm_languages['sh.env'] = vim.deepcopy(efm_languages['sh'])
table.insert(efm_languages['sh.env'], require 'efm/dotenv')
efm_languages['c'] = vim.deepcopy(efm_languages['cpp'])

lspconfig.efm.setup(extend_config({
    filetypes = vim.tbl_keys(efm_languages),
    init_options = {documentFormatting = true, codeAction = true},
    settings = {
        languages = efm_languages
        -- log_level = 1,
        -- log_file = '~/efm.log',
    },
    single_file_support = true
}))

-- https://github.com/mjlbach/defaults.nvim/blob/master/init.lua#L245
-- Make runtime files discoverable to the server
local runtime_path = vim.split(package.path, ';')
table.insert(runtime_path, 'lua/?.lua')
table.insert(runtime_path, 'lua/?/init.lua')

-- https://www.chrisatmachine.com/Neovim/28-neovim-lua-development/
lspconfig.sumneko_lua.setup(extend_config({
    on_attach = function(client, bufnr)
        client.resolved_capabilities.document_formatting = false
        client.resolved_capabilities.document_range_formatting = false
        default_on_attach(client, bufnr)
    end,
    settings = {
        Lua = {
            runtime = {
                -- Tell the language server which version of Lua you're using
                -- (most likely LuaJIT in the case of Neovim)
                version = 'LuaJIT',
                -- Setup your lua path
                path = runtime_path
            },
            diagnostics = {
                -- Get the language server to recognize the `vim` global
                globals = {'vim', 'hs'}
            },
            workspace = {
                -- Make the server aware of Neovim runtime files
                library = vim.api.nvim_get_runtime_file('', true)
            },
            telemetry = {enable = false}
        }
    }
}))

-- https://github.com/golang/tools/blob/master/gopls/doc/vim.md#neovim-config
lspconfig.gopls.setup(default_lsp_config)

-- JavaScript/TypeScript
-- Only formatting, as it's faster than `prettier`.
-- lspconfig.denols.setup(extend_config({
--     on_attach = function(client, bufnr)
--         for k, _ in pairs(client.resolved_capabilities) do
--             client.resolved_capabilities[k] = false
--         end
--         client.resolved_capabilities.document_formatting = true
--         on_attach(client, bufnr)
--     end,
-- }))

-- JavaScript/TypeScript
-- This has an executable called `typescript-language-server` that wraps `tsserver`.
-- For JS, you'll need to crate a `jsconfig.json` file in the root directory:
-- https://github.com/tsconfig/bases/blob/main/bases/node16.json
local npm_path = '/usr/local/bin/npm'
if vim.fn.filereadable(npm_path) == 0 then
    npm_path = '/opt/homebrew/bin/npm'
end
lspconfig.tsserver.setup(extend_config({
    init_options = {npmLocation = npm_path},
    on_attach = function(client, bufnr)
        client.resolved_capabilities.document_formatting = false
        default_on_attach(client, bufnr)
    end
    -- cmd = {
    --     "typescript-language-server", "--stdio", "--tsserver-log-file",
    --     "/Users/adriano/tsserver.log", "--tsserver-log-verbosity", "verbose"
    -- }
}))

-- Docker
lspconfig.dockerls.setup(default_lsp_config)

-- YAML
lspconfig.yamlls.setup(default_lsp_config)

-- Rust
lspconfig.rls.setup(extend_config({
    settings = {rust = {build_on_save = false, all_features = true}}
}))

local default_ltex_configuration =
    require'lspconfig/server_configurations/ltex'.default_config

-- Markdown, LaTeX
lspconfig.ltex.setup(extend_config({
    settings = {
        ltex = {
            dictionary = {
                -- Couldn't make this work, unfortunately, so added `MORFOLOGIK_RULE_EN_US`.
                ['en-US'] = {[[:~/.vim/spell/en.utf-8.add]]}
            },
            additionalRules = {motherTongue = "it"},
            disabledRules = {
                ['en-US'] = {"WHITESPACE_RULE", "MORFOLOGIK_RULE_EN_US"}
            },
            markdown = {
                nodes = {
                    CodeBlock = "ignore",
                    FencedCodeBlock = "ignore",
                    AutoLink = "dummy",
                    Code = "dummy"
                }
            }
        }
    },

    -- https://github.com/neovim/nvim-lspconfig/blob/
    -- 7d5a6dc46dd2ebaeb74b573922f289ae33089fe7/lua/lspconfig/
    -- server_configurations/ltex.lua#L23
    get_language_id = function(_, filetype)
        if filetype == 'markdown.wiki' then return 'markdown' end
        return default_ltex_configuration.get_language_id(_, filetype)
    end
}))

-- Solidity
-- Currently very buggy.
-- lspconfig.solc.setup(default_lsp_config)

lspconfig.ccls.setup(default_lsp_config)

-- cargo install rnix-lsp
lspconfig.rnix.setup(default_lsp_config)

-- https://github.com/artempyanykh/marksman
-- requires manual installation
if vim.fn.executable('marksman') == 1 then
    lspconfig.marksman.setup(extend_config({
        root_dir = util.root_pattern(".git", ".marksman.toml", ".enable_ctags")
    }))
end

local buffer_options_default = require('plugins.utils').buffer_options_default

M.diagnostic_config = {
    virtual_text = function(_, bufnr)
        if buffer_options_default(bufnr, 'show_virtual_text', true) then
            return {prefix = '●', source = "if_many"}
        end
        return false
    end,

    signs = function(_, bufnr)
        return buffer_options_default(bufnr, 'show_signs', false)
    end,

    -- delay update diagnostics
    update_in_insert = function(_, bufnr)
        return buffer_options_default(bufnr, 'update_in_insert', false)
    end,

    severity_sort = true
}

function M.reload_config() vim.diagnostic.config(M.diagnostic_config) end
M.reload_config() -- First time initialization.

-- Remove annoying highlight and lightbulb, just color the line.
vim.fn.sign_define('LightBulbSign', {
    text = "",
    texthl = "",
    linehl = "",
    numhl = "QuickFixLine"
})

require'nvim-lightbulb'.setup {
    ignore = {'pylsp', 'marksman'}, -- LSP client names to ignore
    sign = {
        enabled = true,
        priority = 10 -- Priority of the gutter sign
    },
    float = {enabled = false},
    virtual_text = {enabled = false},
    status_text = {enabled = false}
}

return M

-- Override this LSP handler to open the quickfix in Trouble
-- Inspired by $VIMRUNTIME/lua/vim/lsp/handlers.lua
-- Credits here: https://www.reddit.com/r/vim/comments/osmt4x/help_me_run_vimlspbufreferences_without_opening/
-- vim.lsp.handlers['textDocument/references'] =
--     function(_, result, ctx)
--         if not result or vim.tbl_isempty(result) then return end
--         vim.fn.setqflist({}, ' ', {
--             title = 'Language Server',
--             items = vim.lsp.util.locations_to_items(result, ctx.bufnr)
--         })
--         require'trouble'.open('quickfix')
--     end
