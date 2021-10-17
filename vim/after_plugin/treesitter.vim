if has('nvim')
    " https://github.com/nvim-treesitter/nvim-treesitter#modules
    lua <<EOF
    require'nvim-treesitter.configs'.setup {
        ensure_installed = "maintained",
        highlight = {enable = true},
        indent = {enable = true, disable = {"python", }, },
        incremental_selection = {
            enable = true,
            keymaps = {
                init_selection = "gnn",
                node_incremental = "grn",
                scope_incremental = "grc",
                node_decremental = "grm"
            }
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
                set_jumps = false, -- whether to set jumps in the jumplist
                goto_next_start = {
                    ["]m"] = "@function.outer",
                    ["]]"] = "@class.outer"
                },
                goto_next_end = {
                    ["]M"] = "@function.outer",
                    ["]["] = "@class.outer"
                },
                goto_previous_start = {
                    ["[m"] = "@function.outer",
                    ["[["] = "@class.outer"
                },
                goto_previous_end = {
                    ["[M"] = "@function.outer",
                    ["[]"] = "@class.outer"
                }
            }
        }
    }
EOF
endif
