-- Original credits to
-- https://github.com/tomaskallup/dotfiles/blob/master/nvim/lua/plugins/nvim-lspconfig.lua
local lspconfig = require 'lspconfig'
local util = require('lspconfig.util')
local python = require('aldur.python')

local M = {}

require('aldur.fidget')
require('aldur.code_action') -- Side effects, autocmd

local default_lsp_config = lspconfig.util.default_config

default_lsp_config.capabilities = vim.tbl_deep_extend('force',
                                                      default_lsp_config.capabilities,
                                                      require('cmp_nvim_lsp').default_capabilities())

vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
        local bufnr = args.buf

        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client == nil then return end

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
    markdown = {require 'aldur.efm.mdl', require 'aldur.efm.prettier_markdown'},
    lua = {require 'aldur.efm.luafmt', require 'aldur.efm.luacheck'},
    python = {require 'aldur.efm.black'},
    dockerfile = {require 'aldur.efm.hadolint'},
    vim = {require 'aldur.efm.vint'},
    sh = {require 'aldur.efm.shellcheck', require 'aldur.efm.shfmt'},
    bib = {require 'aldur.efm.bibtool'},
    cpp = {require 'aldur.efm.astyle'},
    json = {require 'aldur.efm.jq'},
    xml = {require 'aldur.efm.xmltidy'},
    solidity = {
        require 'aldur.efm.prettier_solidity', require 'aldur.efm.solhint'
    },
    typescript = {require 'aldur.efm.prettier_typescript'},
    javascript = {require 'aldur.efm.prettier_javascript'},
    scss = {require 'aldur.efm.prettier_scss'},
    env = {require 'aldur.efm.dotenv', require 'aldur.efm.shfmt'}, -- We don't want shellcheck here.
    caddyfile = {require 'aldur.efm.caddyfile'},
    sql = {require 'aldur.efm.sql'},
    beancount = {require 'aldur.efm.bean-format'}
}
efm_languages['markdown.wiki'] = efm_languages['markdown']

efm_languages['yaml.cloudformation'] = {require 'aldur.efm.cfnlint'}

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

            -- WARNING:
            -- Error here, or in all `on_*` functions, will not be printed!
            -- Things will be very difficult to debug.
            -- If you need to debug, use canaries, e.g.:
            -- vim.print(client.config)
        end

        client.notify("workspace/didChangeConfiguration",
                      {settings = client.config.settings})
        return true
    end,
    on_new_config = function(new_config, new_root_dir)
        if new_root_dir then
            ---@diagnostic disable-next-line: undefined-field
            if vim.uv.fs_stat(new_root_dir .. '/.luarc.json') or
                vim.uv.fs_stat(new_root_dir .. '/.luarc.jsonc') then
                return
            end
        end

        if new_root_dir:find('.dotfiles/vim', 1, true) then
            _G.info_message(
                "Overriding lua_lsp configuration for vim lua files.")

            -- https://github.com/mjlbach/defaults.nvim/blob/master/init.lua#L245
            -- Make runtime files discoverable to the server
            local runtime_path = vim.split(package.path, ';')
            table.insert(runtime_path, 'lua/?.lua')
            table.insert(runtime_path, 'lua/?/init.lua')

            new_config.settings.Lua = vim.tbl_deep_extend('force',
                                                          new_config.config
                                                              .settings.Lua, {
                runtime = {version = 'LuaJIT', path = runtime_path},
                diagnostics = {globals = 'vim'},
                workspace = {library = vim.api.nvim_get_runtime_file('', true)}
            })

            -- WARNING:
            -- Error here, or in all `on_*` functions, will not be printed!
            -- Things will be very difficult to debug.
            -- If you need to debug, use canaries, e.g.:
            -- vim.print(client.config)
        end
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
-- This has an executable called `typescript-language-server` that wraps `tsserver`.
-- For JS, you'll need to crate a `jsconfig.json` file in the root directory:
-- https://github.com/tsconfig/bases/blob/main/bases/node16.json
lspconfig.ts_ls.setup(extend_config({
    on_attach = function(client, bufnr)
        client.server_capabilities.documentFormattingProvider = false
        default_on_attach(client, bufnr)
    end
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
    on_attach = function(client, bufnr)
        vim.lsp.inlay_hint.enable(true, {bufnr = bufnr})
        default_on_attach(client, bufnr)
    end,
    on_new_config = function(new_config, new_root_dir)
        -- `direnv` is a no-op if not configured
        _G.info_message("Switching to new root directory '" .. new_root_dir ..
                            "'.")
        new_config['cmd'] = {"direnv", "exec", new_root_dir, "rust-analyzer"}
    end
}))

local default_ltex_configuration =
    require'lspconfig/configs/ltex'.default_config

local spell_directory = vim.fn.stdpath("data") .. "/site/spell/"

-- Markdown, LaTeX
lspconfig.ltex.setup(extend_config({
    flags = {debounce_text_changes = 1000},
    settings = {
        ltex = {
            dictionary = {
                ['en-US'] = {":" .. spell_directory .. "en.utf-8.add"}
            },
            additionalRules = {motherTongue = "it"},
            disabledRules = {['en-US'] = {"WHITESPACE_RULE"}},
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

lspconfig.nil_ls.setup(extend_config({
    settings = {["nil"] = {formatting = {command = {"nixpkgs-fmt"}}}}
}))

-- https://github.com/artempyanykh/marksman
lspconfig.marksman.setup(extend_config({
    root_dir = util.root_pattern(".git", ".marksman.toml", ".enable_ctags"),
    on_attach = function(client, bufnr)
        client.server_capabilities.codeActionProvider = false
        client.server_capabilities.hoverProvider = false
        default_on_attach(client, bufnr)
    end,
    cmd = {"marksman", "server"}
}))

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

-- clarinet
-- FIXME
-- brew install clarinet
if vim.fn.executable('clarinet') == 1 then
    require('clarinet') -- Adds clarinet LSP
    lspconfig.clarinet.setup(default_lsp_config)
end

-- texlab
lspconfig.texlab.setup(default_lsp_config)

local buffer_options_default = require('aldur.utils').buffer_options_default

function M.signs_enabled(bufnr)
    return buffer_options_default(bufnr, 'show_signs', 1) == 1
end
function M.virtual_text_enabled(bufnr)
    return buffer_options_default(bufnr, 'show_virtual_text', 0) == 1
end
function M.update_in_insert_enabled(bufnr)
    return buffer_options_default(bufnr, 'update_in_insert', 0) == 1
end
function M.underline_enabled(bufnr)
    return buffer_options_default(bufnr, 'show_diagnostic_underline', 1) == 1
end

M.diagnostic_config = {
    virtual_text = function(_, bufnr)
        if M.virtual_text_enabled(bufnr) then
            return {prefix = '●', source = "if_many"}
        end
        return false
    end,

    signs = function(_, bufnr) return M.signs_enabled(bufnr) end,

    underline = function(_, bufnr) return M.underline_enabled(bufnr) end,

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
    local name = "LightBulb"
    pcall(vim.api.nvim_del_augroup_by_name, name)
    local id = vim.api.nvim_create_augroup(name, {})
    vim.api.nvim_create_autocmd({"CursorHold", "CursorHoldI"}, {
        pattern = {"*"},
        group = id,
        callback = M.code_action_listener
    })
end

M.code_action_autocmd() -- This creates the autocmd to trigger the lightbulb

function M.diagnostic_autocmd()
    local name = "QFDiagnostic"
    pcall(vim.api.nvim_del_augroup_by_name, name)
    local group = vim.api.nvim_create_augroup(name, {})

    local loclist_title = "LSP Diagnostics"

    local function on_diagnostic_changed(diagnostics)
        vim.diagnostic.setloclist({open = false, title = loclist_title})

        if #diagnostics == 0 then
            vim.cmd("silent! lclose")
        end

        -- Inspired by how lightline.vim refreshes the statusline.
        vim.fn["lightline#update"]()
    end

    vim.api.nvim_create_autocmd({'DiagnosticChanged'}, {
        group = group,
        callback = function(args)
            if (args and args.data) then
                on_diagnostic_changed(args.data.diagnostics)
            end
        end
    })

    -- vim.api.nvim_create_autocmd({'BufEnter'}, {
    --     group = group,
    --     callback = function()
    --         if vim.w.quickfix_title == loclist_title and vim.bo.buftype ==
    --             'quickfix' then
    --             return _G.info_message("Ignoring quickfix...")
    --         end
    --         on_diagnostic_changed(vim.diagnostic.get(0))
    --     end
    -- })
end

M.diagnostic_autocmd() -- This creates the autocmd to populate / update the QF with the diagnostics

-- HACK: Experimental, disable LSP for `gen.nvim` buffers.
local name = "GenNvimLSP"
pcall(vim.api.nvim_del_augroup_by_name, name)
local group = vim.api.nvim_create_augroup(name, {})
vim.api.nvim_create_autocmd({'BufEnter', 'BufNewFile'}, {
    group = group,
    pattern = '^gen.nvim$',
    callback = function() vim.defer_fn(function() vim.cmd 'LspStop' end, 100) end
})

return M
