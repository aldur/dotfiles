-- Original credits to https://github.com/tomaskallup/dotfiles/blob/master/nvim/lua/plugins/nvim-lspconfig.lua
local lspconfig = require 'lspconfig'
local util = require('lspconfig/util')
local python = require('plugins/python')
local M = {}

require("fidget").setup {
    fmt = {
        max_messages = 3,
        task = -- function to format each task line
        function(task_name, message, percentage)
            if message == "Started" then
                message = "..."
            elseif message == "Completed" then
                return nil -- Avoid spam
            else
                if message then
                    message = string.format(": %s", string.lower(message))
                end
            end
            return string.format("%s%s %s", task_name, message, percentage and
                                     string.format(" (%s%%)", percentage) or "")
        end
    }
}

local default_lsp_config = lspconfig.util.default_config

default_lsp_config.capabilities = vim.tbl_deep_extend('force',
                                                      default_lsp_config.capabilities,
                                                      require('cmp_nvim_lsp').default_capabilities())

vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
        local bufnr = args.buf

        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client == nil then return end

        -- Enable completion triggered by <c-x><c-o>
        -- NOTE: No need for this, `nvim` does it better.
        -- It also sets `tagfunc` and `format{prg,expr}`.
        -- https://github.com/neovim/neovim/blob/
        -- bbb934e7755a3b6f14c4d94334b8f54c63daebf1/runtime/lua/vim/lsp.lua#L974
        -- vim.bo[bufnr].omnifunc = 'v:lua.vim.lsp.omnifunc'

        require("lsp_signature").on_attach({
            -- This is mandatory, otherwise border config won't get registered.
            bind = true,
            handler_opts = {border = "single"}
        })

        -- Mappings
        local bufopts = {noremap = true, silent = true, buffer = bufnr}

        if client.server_capabilities.referencesProvider then
            -- Mnemonic for Usages
            vim.keymap.set('n', '<leader>u', vim.lsp.buf.references, bufopts)
        end

        -- Call twice to jump into the window.
        vim.keymap.set('n', 'K', function()
            local lnum, cnum = unpack(vim.api.nvim_win_get_cursor(0))
            -- XXX: For some reasons, have to subtract 1 to nvim's line.
            local diagnostics = vim.diagnostic.get(0, {lnum = lnum - 1})

            -- Diagnostic, if any.
            if #diagnostics then
                for _, d in ipairs(diagnostics) do
                    if cnum >= d["col"] and cnum < d["end_col"] then
                        -- Found, early exit.
                        return vim.diagnostic.open_float()
                    end
                end
            end

            if client.server_capabilities.hoverProvider then
                -- Hover, if available.
                vim.lsp.buf.hover()
            else
                -- Fallback to `investigate` plugin.
                vim.fn['investigate#Investigate']('n')
            end
        end, bufopts)

        if client.server_capabilities.codeActionProvider then
            vim.keymap.set({'n', 'x'}, 'gK',
                           require("actions-preview").code_actions, bufopts)
        end

        if client.server_capabilities.documentFormattingProvider then
            vim.keymap.set('n', '<leader>f',
                           function()
                vim.lsp.buf.format({async = true})
            end, bufopts)
        end

        -- NOTE: This should not be required since `nvim` sets `formatexpr`
        -- if client.server_capabilities.documentRangeFormattingProvider then
        --     local f = function()
        --         vim.lsp.buf.format({async = false, timeout_ms = 1000})
        --     end
        --     vim.keymap.set({'n', 'x'}, 'gq', f)
        -- end

        -- NOTE: This should not be required since `nvim` sets `tagsfunc`
        -- This overrides the default mapping to look up `tags`
        -- if client.server_capabilities.definitionProvider then
        --     vim.keymap.set('n', '<c-]>', vim.lsp.buf.definition, bufopts)
        -- end

        -- Our LSP configuration places diagnostic in the loclist.
        -- This overrides the default commands to go to prev/next element in the
        -- loclist. It has the advantage to take the cursor position into consideration.
        local diagnostic_goto_opts = {float = false}
        vim.keymap.set('n', '[l', function()
            vim.diagnostic.goto_prev(diagnostic_goto_opts)
        end, bufopts)
        vim.keymap.set('n', ']l', function()
            vim.diagnostic.goto_next(diagnostic_goto_opts)
        end, bufopts)
    end
})

vim.api.nvim_create_autocmd("LspDetach", {
    callback = function(_)
        -- local client = vim.lsp.get_client_by_id(args.data.client_id)
        -- Do something with the client

        -- TODO: Unset keymaps.
        -- vim.cmd("setlocal tagfunc< omnifunc<")

        -- Here we refresh buffer diagnostic to avoid stale ones
        -- (from the LSP that was detached).
        vim.diagnostic.reset()
        vim.diagnostic.get(0)
    end
})

-- In case you need to setup additional things on attach, here you have a
-- default function. Takes `client` and `bufnr`.
local default_on_attach = function(_, _) end
default_lsp_config.on_attach = default_on_attach

local function extend_config(tbl)
    return vim.tbl_deep_extend('force', default_lsp_config, tbl)
end

-- Python pyright
lspconfig.pyright.setup(extend_config({
    before_init = function(_, config)
        config.settings.python.pythonPath =
            python.find_python_path(config.root_dir)
    end
}))

-- Inspired by:
-- https://github.com/python-lsp/python-lsp-server/pull/68
local function pylsp_cmd_env(workspace)
    local venv = python.find_python_venv(workspace)
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
        -- https://microsoft.github.io/language-server-protocol/specifications
        -- /lsp/3.17/specification/#textDocument_hover
        client.server_capabilities.documentFormattingProvider = false
        client.server_capabilities.completionProvider = false
        client.server_capabilities.documentHighlightProvider = false
        client.server_capabilities.documentRangeFormattingProvider = false
        client.server_capabilities.referencesProvider = false
        client.server_capabilities.definitionProvider = false
        client.server_capabilities.executeCommandProvider = true
        client.server_capabilities.documentSymbolProvider = false
        client.server_capabilities.hoverProvider = false
        client.server_capabilities.renameProvider = false
        client.server_capabilities.signatureHelpProvider = false
        client.server_capabilities.codeLensProvider = false
        client.server_capabilities.codeActionProvider = true
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
    javascript = {require 'efm/prettier_javascript'},
    scss = {require 'efm/prettier_scss'},
    env = {require 'efm/dotenv', require 'efm/shfmt'}, -- We don't want shellcheck here.
    caddyfile = {require 'efm/caddyfile'},
    sql = {require 'efm/sql'},
    beancount = {require 'efm/bean-format'}
}
efm_languages['markdown.wiki'] = efm_languages['markdown']

efm_languages['yaml.cloudformation'] = {require 'efm/cfnlint'}

efm_languages['c'] = vim.deepcopy(efm_languages['cpp'])

lspconfig.efm.setup(extend_config({
    filetypes = vim.tbl_keys(efm_languages),
    init_options = {
        documentFormatting = true,
        codeAction = true,
        completion = true,
        hover = true
    },
    settings = {
        languages = efm_languages
        -- log_level = 1,
        -- log_file = '~/efm.log',
    },
    single_file_support = true
}))

-- https://www.chrisatmachine.com/Neovim/28-neovim-lua-development/
lspconfig.lua_ls.setup(extend_config({
    on_attach = function(client, bufnr)
        client.server_capabilities.documentFormattingProvider = false
        client.server_capabilities.documentRangeFormattingProvider = false
        default_on_attach(client, bufnr)
    end,
    on_init = function(client)
        local path = client.workspace_folders[1].name

        if path:find('.vim', 1, true) or path:find('.dotfiles/vim', 1, true) then
            _G.info_message(
                "Overriding lua_lsp configuration for vim lua files.")

            -- https://github.com/mjlbach/defaults.nvim/blob/master/init.lua#L245
            -- Make runtime files discoverable to the server
            local runtime_path = vim.split(package.path, ';')
            table.insert(runtime_path, 'lua/?.lua')
            table.insert(runtime_path, 'lua/?/init.lua')

            -- Tell the language server which version of Lua you're using
            -- (most likely LuaJIT in the case of Neovim)
            client.config.settings.Lua.runtime.version = "LuaJIT"
            -- Setup your lua path
            client.config.settings.Lua.runtime.path = runtime_path
            -- Get the language server to recognize the `vim` global
            client.config.settings.Lua.diagnostics.globals = {'vim'}

            -- Make the server aware of Neovim runtime files
            local f = vim.api.nvim_get_runtime_file
            client.config.settings.Lua.workspace.library = f('', true)

            -- WARNING: An error here will not be printed, so it will be very
            -- difficult to debug.
            -- If you need to debug, use this as a canary.
            -- vim.print(client.config)
        end

        client.notify("workspace/didChangeConfiguration",
                      {settings = client.config.settings})
        return true
    end,
    -- NOTE: If you need to debug the LSP.
    -- cmd = {
    --     "lua-language-server", "--logpath", "/tmp/.cache/lua-language-server/",
    --     "--metapath", "/tmp/.cache/lua-language-server/meta/"
    -- },
    settings = {
        Lua = {
            runtime = {version = 'Lua 5.4'},
            workspace = {checkThirdParty = false},
            diagnostics = {globals = {}},
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
--         for k, _ in pairs(client.server_capabilities) do
--             client.server_capabilities[k] = false
--         end
--         client.server_capabilities.documentFormattingProvider = true
--         on_attach(client, bufnr)
--     end,
-- }))

-- JavaScript/TypeScript
-- This has an executable called `typescript-language-server` that wraps `tsserver`.
-- For JS, you'll need to crate a `jsconfig.json` file in the root directory:
-- https://github.com/tsconfig/bases/blob/main/bases/node16.json
local npm_path = '/usr/local/bin/npm'
if vim.fn.filereadable(npm_path) == 0 then npm_path = '/opt/homebrew/bin/npm' end
lspconfig.tsserver.setup(extend_config({
    init_options = {npmLocation = npm_path},
    on_attach = function(client, bufnr)
        client.server_capabilities.documentFormattingProvider = false
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
lspconfig.yamlls.setup(extend_config({
    on_attach = function(client, bufnr)
        client.server_capabilities.documentFormattingProvider = true
        default_on_attach(client, bufnr)
    end,
    settings = {
        redhat = {telemetry = {enabled = false}},
        yaml = {keyOrdering = false}
    }
}))

local rust_analyzer_cmd = {"rustup", "run", "stable", "rust-analyzer"}
if vim.fn.executable('rust-analyzer') == 1 then
    rust_analyzer_cmd = {"rust-analyzer"}
end

-- Rust
lspconfig.rust_analyzer.setup(extend_config({
    settings = {
        ["rust-analyzer"] = {
            imports = {granularity = {group = "module"}, prefix = "self"},
            cargo = {buildScripts = {enable = true}},
            procMacro = {enable = true},
            checkOnSave = {
                allFeatures = true,
                overrideCommand = {
                    'cargo', 'clippy', '--workspace', '--message-format=json',
                    '--all-targets', '--all-features', '--', '-W',
                    'clippy::pedantic'
                }
            }
        }
    },
    cmd = rust_analyzer_cmd
}))

local default_ltex_configuration =
    require'lspconfig/server_configurations/ltex'.default_config

-- Markdown, LaTeX
lspconfig.ltex.setup(extend_config({
    flags = {debounce_text_changes = 1000},
    -- cmd = {"ltex-ls", "--log-file=/tmp/ltex.log"},
    settings = {
        ltex = {
            dictionary = {
                -- Couldn't make this work, unfortunately, so added
                -- `MORFOLOGIK_RULE_EN_US`.
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
            },
            checkFrequency = "edit"
        }
    },

    -- https://github.com/neovim/nvim-lspconfig/blob/
    -- 7d5a6dc46dd2ebaeb74b573922f289ae33089fe7/lua/lspconfig/
    -- server_configurations/ltex.lua#L23
    get_language_id = function(_, filetype)
        if filetype == 'markdown.wiki' then return 'markdown' end
        return default_ltex_configuration.get_language_id(_, filetype)
    end,

    filetypes = vim.tbl_deep_extend('force',
                                    default_ltex_configuration.filetypes,
                                    {'markdown.wiki'})
}))

-- Solidity
-- Currently very buggy.
-- lspconfig.solc.setup(default_lsp_config)

lspconfig.ccls.setup(default_lsp_config)

-- nix profile install nixpkgs#nil nixpkgs#nixpkgs-fmt
lspconfig.nil_ls.setup(extend_config({
    settings = {["nil"] = {formatting = {command = {"nixpkgs-fmt"}}}}
}))

-- https://github.com/artempyanykh/marksman
if vim.fn.executable('marksman') == 1 then
    lspconfig.marksman.setup(extend_config({
        root_dir = util.root_pattern(".git", ".marksman.toml", ".enable_ctags"),
        on_attach = function(client, bufnr)
            client.server_capabilities.codeActionProvider = false
            client.server_capabilities.hoverProvider = false
            default_on_attach(client, bufnr)
        end,
        cmd = {"marksman", "server"}
    }))
end

lspconfig.eslint.setup(extend_config({
    on_attach = function(client, bufnr)
        client.server_capabilities.documentFormattingProvider = true
        default_on_attach(client, bufnr)
    end
}))

-- Terraform
lspconfig.terraformls.setup(default_lsp_config)
lspconfig.tflint.setup(default_lsp_config)

-- cssls
-- Enable (broadcasting) snippet capability for completion
local cssls_config = extend_config({})
cssls_config.capabilities.textDocument.completion.completionItem.snippetSupport =
    true
lspconfig.cssls.setup(cssls_config)

-- html
-- Enable (broadcasting) snippet capability for completion
local html_config = extend_config({})
html_config.capabilities.textDocument.completion.completionItem.snippetSupport =
    true
lspconfig.html.setup(html_config)

-- Liquid
lspconfig.theme_check.setup(default_lsp_config)

-- beancount
-- nix profile install nixpkgs#beancount-language-server
-- lspconfig.beancount.setup {
--     init_options = {journal_file = "/Users/aldur/Documents/Beans/index.beancount"}
-- }

-- clarinet
-- brew install clarinet
require('clarinet') -- Adds clarinet LSP
lspconfig.clarinet.setup(default_lsp_config)

-- texlab
-- brew install texlab
lspconfig.texlab.setup(default_lsp_config)

local buffer_options_default = require('plugins.utils').buffer_options_default

function M.signs_enabled(bufnr)
    return buffer_options_default(bufnr, 'show_signs', 1) == 1
end
function M.virtual_text_enabled(bufnr)
    return buffer_options_default(bufnr, 'show_virtual_text', 0) == 1
end
function M.update_in_insert_enabled(bufnr)
    return buffer_options_default(bufnr, 'update_in_insert', 0) == 1
end

M.diagnostic_config = {
    virtual_text = function(_, bufnr)
        if M.virtual_text_enabled(bufnr) then
            return {prefix = '●', source = "if_many"}
        end
        return false
    end,

    signs = function(_, bufnr) return M.signs_enabled(bufnr) end,

    -- delay update diagnostics
    update_in_insert = function(_, bufnr)
        return M.update_in_insert_enabled(bufnr)
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
    numhl = "DiagnosticOk"
})

local LB_SIGN_GROUP = "nvim-lightbulb"
local LB_SIGN_NAME = "LightBulbSign"
local LB_SIGN_PRIORITY = 25
M.LB_CLIENTS_TO_IGNORE = {'pylsp'}

function M._update_sign(priority, old_line, new_line, bufnr)
    bufnr = bufnr or "%"

    if old_line then
        vim.fn.sign_unplace(LB_SIGN_GROUP, {id = old_line, buffer = bufnr})

        -- Update current lightbulb line
        vim.b.lightbulb_line = nil -- luacheck: ignore 122
    end

    -- Avoid redrawing lightbulb if code action line did not change
    if new_line and (vim.b.lightbulb_line ~= new_line) then
        vim.fn.sign_place(new_line, LB_SIGN_GROUP, LB_SIGN_NAME, bufnr,
                          {lnum = new_line, priority = priority})
        -- Update current lightbulb line
        vim.b.lightbulb_line = new_line -- luacheck: ignore 122
    end
end

-- Taken from https://github.com/neovim/nvim-lspconfig/wiki/Code-Actions
function M.code_action_listener()
    local method = "textDocument/codeAction"
    -- Check for code action capability
    local code_action_cap_found = false
    for _, client in pairs(vim.lsp.get_clients({bufnr = 0, method = method})) do
        if not vim.tbl_contains(M.LB_CLIENTS_TO_IGNORE, client.name) then
            code_action_cap_found = true
            break
        end
    end

    if not code_action_cap_found then return end
    local params = vim.lsp.util.make_range_params()

    local line = params.range.start.line

    local context = {diagnostics = vim.diagnostic.get(0, {lnum = line})}
    params.context = context

    vim.lsp.buf_request_all(0, method, params, function(responses)
        local has_actions = false
        for client_id, resp in pairs(responses) do
            if resp.result and
                not vim.tbl_contains(M.LB_CLIENTS_TO_IGNORE, client_id) and
                not vim.tbl_isempty(resp.result) then
                has_actions = true
                break
            end
        end

        if has_actions then
            M._update_sign(LB_SIGN_PRIORITY, vim.b.lightbulb_line, line + 1)
        else
            M._update_sign(LB_SIGN_PRIORITY, vim.b.lightbulb_line, nil)
        end
    end)
end

function M.code_action_autocmd()
    local id = vim.api.nvim_create_augroup("LightBulb", {})
    vim.api.nvim_create_autocmd({"CursorHold", "CursorHoldI"}, {
        pattern = {"*"},
        group = id,
        callback = M.code_action_listener
    })
end

M.code_action_autocmd() -- This creates the autocmd to trigger the lightbulb

function M.diagnostic_autocmd()
    local group = vim.api.nvim_create_augroup("QFDiagnostic", {})

    local on_diagnostic_changed = function(diagnostics)
        if #diagnostics then
            vim.diagnostic.setloclist({open = false})
        else
            vim.cmd("lclose")
        end
    end

    vim.api.nvim_create_autocmd({'DiagnosticChanged'}, {
        group = group,
        callback = function(args)
            if (args and args.data) then
                on_diagnostic_changed(args.data.diagnostics)
            end
        end
    })

    vim.api.nvim_create_autocmd({'BufEnter'}, {
        group = group,
        callback = function()
            on_diagnostic_changed(vim.diagnostic.get(0))
        end
    })
end

M.diagnostic_autocmd() -- This creates the autocmd to populate / update the QF with the diagnostics

return M
