if has('nvim')
    " https://github.com/nvim-treesitter/nvim-treesitter#modules
    lua <<EOF
    require'nvim-treesitter.configs'.setup {
        ensure_installed = "maintained",
        highlight = {enable = true},
        indent = {enable = true, disable = {"python", }, },
        textsubjects = {
            enable = true,
            keymaps = {
                ['.'] = 'textsubjects-smart',
                [';'] = 'textsubjects-container-outer',
            }
        },
        incremental_selection = {
            enable = false,  -- Replaced by `textsubjects`
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
EOF

    " Show function / class context on top.
    " See `nvim`-treesitter-context
    TSContextEnable
endif
