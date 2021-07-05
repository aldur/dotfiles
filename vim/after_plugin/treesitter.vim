if has('nvim')
    " https://github.com/nvim-treesitter/nvim-treesitter#modules

    lua <<EOF
    require'nvim-treesitter.configs'.setup {
        ensure_installed = "maintained",
        highlight = {
            enable = true,
        },
        indent = {
            enable = true
        }
    }
EOF
endif
