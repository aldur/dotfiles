-- vim: foldmethod=marker foldmarker=[[[,]]]
-- Original credits to
-- https://github.com/tomaskallup/dotfiles/blob/master/nvim/lua/plugins/nvim-lspconfig.lua
local M = {}

local util = require('lspconfig.util')
local default_cfg = util.default_config

local function extend_config(tbl)
    return vim.tbl_deep_extend('force', default_cfg, tbl)
end

default_cfg = extend_config({
    capabilities = require('cmp_nvim_lsp').default_capabilities(),
    on_init = function(client, _)
        -- Disabling full semantic highlight as I am not using it for the time
        -- being.
        -- https://gist.github.com/swarn/fb37d9eefe1bc616c2a7e476c0bc0316?
        --   permalink_comment_id=5210704#gistcomment-5210704
        client.server_capabilities.semanticTokensProvider = nil
    end
})

-- In case you need to setup additional things on attach, here is a default
-- function. It takes `client` and `bufnr`.
default_cfg.on_attach = function(_, _) end

local TRACE = vim.log.levels.TRACE
local INFO = vim.log.levels.INFO
local function log(msg, level)
    if level == nil then level = INFO end
    if level > vim.log.levels.TRACE or vim.lsp.log.get_level() <= level then
        vim.notify("LSP: " .. msg, level)
    end
end

util.on_setup = util.add_hook_before(util.on_setup, function(config, _)
    local function direnv_on_new_config(new_config, new_root_dir)
        log("Switching to new root directory '" .. new_root_dir .. "'.", TRACE)
        -- NOTE: `cmd` here has been "sanitized" to its full path.
        local cmd = vim.list_extend({"direnv", "exec", new_root_dir},
                                    new_config.cmd)
        log("Switching to new cmd: '" .. vim.inspect(cmd), TRACE)
        new_config['cmd'] = cmd
        new_config['cmd_cwd'] = new_root_dir
        -- TODO: We could be using `cmd_env` instead.
    end

    config.on_new_config = util.add_hook_after(config.on_new_config,
                                               direnv_on_new_config)
end)

local lspconfig = require('lspconfig')

-- Python [[[1

local python = require('aldur.python')

-- https://github.com/DetachHead/basedpyright
lspconfig.basedpyright.setup(extend_config({
    before_init = function(_, config)
        config.settings.python = {
            pythonPath = python.find_python_path(config.root_dir)
        }
        config.python = config.settings.python
    end,
    basedpyright = {
        -- Using Ruff's import organizer
        disableOrganizeImports = true,
        analysis = {
            autoImportCompletions  = true,
        }
    }
}))

lspconfig.ruff.setup(extend_config({
    -- TODO: Point to Python path
    -- trace = 'messages',
    init_options = {
        settings = {
            -- logLevel = 'debug',
            lineLength = 100,
            lint = {
                select = {
                    "E", -- pycodestyle
                    "F", -- Pyflakes
                    "UP", -- pyupgrade
                    "B", -- flake8-bugbear
                    "SIM", -- flake8-simplify
                    "I" -- isort
                }
            }
        }
    }
}))

-- ]]]

-- EFM [[[1
local vint = require 'efmls-configs.linters.vint'
vint.lintCommand = vint.lintCommand .. " --enable-neovim"

-- Formatting/linting via efm
local efm_languages = {
    markdown = {require 'aldur.efm.mdl', require 'aldur.efm.prettier_markdown'},
    lua = {
        require 'aldur.efm.luafmt' -- require 'aldur.efm.luacheck'
    },
    dockerfile = {require('efmls-configs.linters.hadolint')},
    vim = {vint},
    sh = {
        require 'efmls-configs.linters.shellcheck',
        require 'efmls-configs.formatters.shfmt'
    },
    bib = {require 'aldur.efm.bibtool'},
    cpp = {require 'aldur.efm.astyle'},
    json = {
        require 'efmls-configs.formatters.jq',
        require 'efmls-configs.linters.jq'
    },
    xml = {require 'aldur.efm.xmltidy'},
    solidity = {
        require 'aldur.efm.prettier_solidity', require 'aldur.efm.solhint'
    },
    typescript = {require 'aldur.efm.prettier_typescript'},
    javascript = {require 'aldur.efm.prettier_javascript'},
    scss = {require 'aldur.efm.prettier_scss'},
    env = {
        -- We don't want shellcheck here.
        require 'aldur.efm.dotenv', require 'efmls-configs.formatters.shfmt'
    },
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
        documentRangeFormatting = true,
        codeAction = true,
        completion = true,
        hover = true
    },
    settings = {
        languages = efm_languages,
        log_level = 1,
        log_file = '/tmp/efm.log'
    },
    single_file_support = true
}))

-- ]]]

-- lua [[[1

local lua_ls_on_init = function(client)
    local path = client.workspace_folders[1].name

    if path:find('.vim', 1, true) or path:find('.dotfiles/neovim', 1, true) then
        log("Overriding lua_lsp configuration for vim lua files.")

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
end

lspconfig.lua_ls.setup(extend_config({
    on_attach = function(client, bufnr)
        client.server_capabilities.documentFormattingProvider = false
        client.server_capabilities.documentRangeFormattingProvider = false
        default_cfg.on_attach(client, bufnr)
    end,
    on_init = util.add_hook_before(default_cfg.on_init, lua_ls_on_init),
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
            log("Overriding lua_lsp configuration for vim lua files.")

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

-- ]]]

-- ltex [[[1

local default_ltex_configuration =
    require'lspconfig/configs/ltex'.default_config

local ltex_filetypes = default_ltex_configuration.filetypes

for idx, ft in ipairs(ltex_filetypes) do
    if ft == 'gitcommit' then table.remove(ltex_filetypes, idx) end
end
ltex_filetypes = vim.tbl_deep_extend('force', ltex_filetypes, {'markdown.wiki'})

local ltex_disabled_rules = {
    "WHITESPACE_RULE", "MORFOLOGIK_RULE_EN_US", "EN_QUOTES"
}

-- Markdown, LaTeX
lspconfig.ltex.setup(extend_config({
    settings = {
        ltex = {
            additionalRules = {
                motherTongue = "it"
                -- NOTE: This needs to be disabled, otherwise the rules it enables
                -- can't be disabled.
                -- enablePickyRules = true
            },
            disabledRules = {
                ['en-US'] = ltex_disabled_rules,
                it = ltex_disabled_rules
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

    filetypes = ltex_filetypes,

    -- https://github.com/neovim/nvim-lspconfig/blob/
    -- 7d5a6dc46dd2ebaeb74b573922f289ae33089fe7/lua/lspconfig/
    -- server_configurations/ltex.lua#L23
    get_language_id = function(_, filetype)
        if filetype == 'markdown.wiki' then return 'markdown' end
        return default_ltex_configuration.get_language_id(_, filetype)
    end

    ---@diagnostic disable-next-line: unused-local
    -- on_attach = function(_client, _bufnr)
    --     require("ltex_extra").push_setting("disabledRules", "en-US",
    --                                        ltex_disabled_rules)
    --     require("ltex_extra").push_setting("disabledRules", "it",
    --                                        ltex_disabled_rules)
    -- end
}))

-- NOTE: Tried to make `ltex` work with default `vim` dictionary, to no result.
-- This plugin handles its own dictionary (why?!).
---@diagnostic disable-next-line: missing-fields
-- require("ltex_extra").setup({
--     load_langs = {'en-US', 'it'},
--     path = vim.fn.stdpath("data") .. "/ltex"
-- })

-- ]]]

-- nix [[[1

lspconfig.autotools_ls.setup(default_cfg)

lspconfig.nil_ls.setup(extend_config({
    settings = {["nil"] = {formatting = {command = {"nixfmt"}}}}
}))

-- nixd
lspconfig.nixd.setup({
    cmd = {"nixd"},
    settings = {
        nixd = {
            nixpkgs = {expr = "import <nixpkgs> { }"},
            -- formatting = {command = {"nixfmt"}},
            options = {
                nixos = {
                    -- TODO: Make this generic!
                    -- https://github.com/nix-community/nixd/issues/608
                    expr = '(builtins.getFlake "/Users/aldur/.dotfiles/osx/").darwinConfigurations.Maui.options'
                }
            }
        }
    }
})

-- ]]]

-- markdown [[[1

-- https://github.com/artempyanykh/marksman
lspconfig.marksman.setup(extend_config({
    root_dir = util.root_pattern(".git", ".marksman.toml", ".enable_ctags"),
    on_attach = function(client, bufnr)
        client.server_capabilities.codeActionProvider = false
        client.server_capabilities.hoverProvider = false
        default_cfg.on_attach(client, bufnr)
    end
}))

-- ]]]

-- Harper [[[1

lspconfig.harper_ls.setup(extend_config({
    settings = {
        ["harper-ls"] = {
            linters = {
                spell_check = true,
                spelled_numbers = false,
                an_a = true,
                sentence_capitalization = true,
                unclosed_quotes = true,
                wrong_quotes = false,
                long_sentences = true,
                repeated_words = true,
                spaces = true,
                matcher = true,
                correct_number_suffix = true,
                number_suffix_capitalization = true,
                multiple_sequential_pronouns = true,
                linking_verbs = true,
                avoid_curses = true,
                terminating_conjunctions = true
            }
        }
    },
    filetypes = {"markdown", "markdown.wiki"} -- Annoyingly, `harper` tries to lint all files.
}))

-- ]]]

-- LaTeX [[[1

-- texlab
lspconfig.texlab.setup(default_cfg)

-- ]]]

-- Vim [[[1

-- Vim lsp
lspconfig.vimls.setup(extend_config({flags = {debounce_text_changes = 500}}))

-- ]]]

-- JavaScript/TypeScript [[[1

lspconfig.eslint.setup(extend_config({
    on_attach = function(client, bufnr)
        client.server_capabilities.documentFormattingProvider = true
        default_cfg.on_attach(client, bufnr)
    end
}))

-- JavaScript/TypeScript
-- This has an executable called `typescript-language-server` that wraps `tsserver`.
-- For JS, you'll need to crate a `jsconfig.json` file in the root directory:
-- https://github.com/tsconfig/bases/blob/main/bases/node16.json
lspconfig.ts_ls.setup(extend_config({
    on_attach = function(client, bufnr)
        client.server_capabilities.documentFormattingProvider = false
        default_cfg.on_attach(client, bufnr)
    end
}))

-- ]]]

-- Terraform [[[1

-- Terraform
lspconfig.terraformls.setup(default_cfg)
lspconfig.tflint.setup(default_cfg)

-- ]]]

-- C/C++ [[[1

lspconfig.ccls.setup(default_cfg)

-- ]]]

-- HTML / CSS [[[1

-- Enable (broadcasting) snippet capability for completion
local html_config = extend_config({})
html_config.capabilities.textDocument.completion.completionItem.snippetSupport =
    true
lspconfig.html.setup(html_config)

-- cssls
-- Enable (broadcasting) snippet capability for completion
local cssls_config = extend_config({})
cssls_config.capabilities.textDocument.completion.completionItem.snippetSupport =
    true
lspconfig.cssls.setup(cssls_config)

-- ]]]

-- Go [[[1

lspconfig.gopls.setup(default_cfg)

-- ]]]

-- Docker [[[1

lspconfig.dockerls.setup(default_cfg)

-- ]]]

-- Beancount [[[1

lspconfig.beancount.setup(extend_config({
    on_attach = function(client, bufnr)
        client.server_capabilities.documentFormattingProvider = false
        client.server_capabilities.documentRangeFormattingProvider = false
        default_cfg.on_attach(client, bufnr)
    end
}))

-- ]]]

-- YAML [[[1

lspconfig.yamlls.setup(extend_config({
    on_attach = function(client, bufnr)
        client.server_capabilities.documentFormattingProvider = true
        default_cfg.on_attach(client, bufnr)
    end,
    settings = {
        redhat = {telemetry = {enabled = false}},
        yaml = {keyOrdering = false}
    }
}))

-- ]]]

-- Clarity [[[
-- FIXME
require('clarinet') -- Adds clarinet LSP
lspconfig.clarinet.setup(extend_config({
    cmd = {'/run/current-system/sw/bin/bash', '/tmp/wrapper.sh'},
    init_options = {completion = true}
}))

-- ]]]

-- Rust [[[[

vim.g.rustaceanvim = {
    server = {
        auto_attach = function(bufnr)
            -- This is taken verbatim from `rustaceanvim.config.internal`.
            -- We only check the first two options, without calling `cmd`,
            -- that would have the following `vim.notify` line executed twice.
            -- NOTE: Remove this if you remove `vim.notify` as default behavior will be
            -- good enough.
            if #vim.bo[bufnr].buftype > 0 then return false end
            local path = vim.api.nvim_buf_get_name(bufnr)
            if not require('rustaceanvim.os').is_valid_file_path(path) then
                return false
            end
            return true
        end,
        cmd = function()
            local rustacean_config = require('rustaceanvim.config.internal')
            local logfile = rustacean_config.server.logfile
            local bufnr = vim.api.nvim_get_current_buf()
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            ---@diagnostic disable-next-line: missing-parameter
            local root_dir = rustacean_config.server.root_dir(bufname)
            vim.notify("Overriding rustacean_config with direnv " .. root_dir,
                       vim.log.levels.INFO)
            return {
                "direnv", "exec", root_dir, 'rust-analyzer', '--log-file',
                logfile
            }
        end
    }
}

-- ]]]]

return M
