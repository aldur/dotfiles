-- Original credits to
-- https://github.com/tomaskallup/dotfiles/blob/master/nvim/lua/plugins/nvim-lspconfig.lua
local lspconfig = require 'lspconfig'
local util = require('lspconfig.util')
local python = require('aldur.python')

local M = {}

local default_lsp_config = lspconfig.util.default_config

default_lsp_config.capabilities = vim.tbl_deep_extend('force',
                                                      default_lsp_config.capabilities,
                                                      require('cmp_nvim_lsp').default_capabilities())

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
                ---@diagnostic disable-next-line: undefined-field
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
                allFeatures = true
                -- overrideCommand = {
                --     'cargo', 'clippy', '--workspace', '--message-format=json',
                --     '--all-targets', '--all-features', '--', '-W',
                --     'clippy::pedantic'
                -- }
            }
        }
    },
    on_new_config = function(new_config, new_root_dir)
        -- `direnv` is a no-op if not configured
        _G.info_message("Switching to new root directory '" .. new_root_dir ..
                            "'.")
        new_config['cmd'] = {"direnv", "exec", new_root_dir, "rust-analyzer"}
        new_config['cmd_cwd'] = new_root_dir
    end
}))

local default_ltex_configuration =
    require'lspconfig/configs/ltex'.default_config

-- Markdown, LaTeX
lspconfig.ltex.setup(extend_config({
    settings = {
        ltex = {
            additionalRules = {motherTongue = "it", enablePickyRules = true},
            disabledRules = {
                ['en-US'] = {
                    "WHITESPACE_RULE", "MORFOLOGIK_RULE_EN_US",
                    "MORFOLOGIK_RULE_IT_IT"
                }
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
    end,

    filetypes = vim.tbl_deep_extend('force',
                                    default_ltex_configuration.filetypes,
                                    {'markdown.wiki'})
}))

-- NOTE: Tried to make `ltex` work with default `vim` dictionary, to no result.
-- This plugin handles its own dictionary (why?!).
-- The MORFOLOGIK_RULE_EN_US is disabled anyway, so that shouldn't bother us.
---@diagnostic disable-next-line: missing-fields
require("ltex_extra").setup({
    load_langs = {'en-US', 'it-IT'},
    path = vim.fn.stdpath("data") .. "/ltex"
})

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
