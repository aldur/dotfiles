-- https://github.com/nvim-treesitter/nvim-treesitter#modules
require'nvim-treesitter.configs'.setup {
    ensure_installed = "all",
    highlight = {enable = true},
    indent = {enable = true, disable = {"python"}},
    textsubjects = {
        enable = true,
        keymaps = {
            ['.'] = 'textsubjects-smart',
            [';'] = 'textsubjects-container-outer'
        }
    },
    incremental_selection = {
        enable = false -- Replaced by `textsubjects`
        -- keymaps = {
        --    init_selection = "gnn",
        --    node_incremental = "gnn",
        --    node_decremental = "gnN",
        --    scope_incremental = "grc",
        -- }
    },
    textobjects = {
        select = {
            enable = true,

            -- Automatically jump forward to textobj, similar to targets.vim
            lookahead = true,

            keymaps = {
                -- You can use the capture groups defined in textobjects.scm
                ["af"] = "@function.outer",
                ["if"] = "@function.inner",
                ["ac"] = "@class.outer",
                ["ic"] = "@class.inner",

                -- "a" is a mnemonic for argument.
                ["aa"] = "@parameter.outer",
                ["ia"] = "@parameter.inner"
            }
        },
        move = {
            enable = true,
            set_jumps = true, -- whether to set jumps in the jumplist
            goto_next_start = {
                ["]m"] = "@function.outer",
                ["]f"] = "@function.outer",
                ["]c"] = "@class.outer"
            },
            goto_next_end = {
                ["]M"] = "@function.outer",
                ["]F"] = "@function.outer",
                ["]C"] = "@class.outer"
            },
            goto_previous_start = {
                ["[m"] = "@function.outer",
                ["[f"] = "@function.outer",
                ["[c"] = "@class.outer"
            },
            goto_previous_end = {
                ["[M"] = "@function.outer",
                ["[F"] = "@function.outer",
                ["[C"] = "@class.outer"
            }
        }
    }
}

require'treesitter-context'.setup {
    enable = true, -- Enable this plugin (Can be enabled/disabled later via commands)
    max_lines = 0, -- How many lines the window should span. Values <= 0 mean no limit.
    trim_scope = 'outer', -- Which context lines to discard if `max_lines` is exceeded. Choices: 'inner', 'outer'
    patterns = { -- Match patterns for TS nodes. These get wrapped to match at word boundaries.
        -- For all filetypes
        -- Note that setting an entry here replaces all other patterns for this entry.
        -- By setting the 'default' entry below, you can control which nodes you want to
        -- appear in the context window.
        default = {
            'class', 'function', 'method'
            -- 'for', -- These won't appear in the context
            -- 'while',
            -- 'if',
            -- 'switch',
            -- 'case',
        }
        -- Example for a specific filetype.
        -- If a pattern is missing, *open a PR* so everyone can benefit.
        --   rust = {
        --       'impl_item',
        --   },
    },
    exact_patterns = {
        -- Example for a specific filetype with Lua patterns
        -- Treat patterns.rust as a Lua pattern (i.e "^impl_item$" will
        -- exactly match "impl_item" only)
        -- rust = true,
    },

    -- [!] The options below are exposed but shouldn't require your attention,
    --     you can safely ignore them.

    zindex = 20, -- The Z-index of the context window
    mode = 'cursor' -- Line used to calculate context. Choices: 'cursor', 'topline'
}
