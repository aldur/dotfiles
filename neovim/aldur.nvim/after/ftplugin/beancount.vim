compiler beancount

setlocal formatprg=bean-format

setlocal comments=b:;
setlocal commentstring=;\ %s

setlocal iskeyword+=:
setlocal iskeyword+=-

setlocal formatoptions+=r
setlocal formatoptions+=o

let b:undo_ftplugin = 'setlocal iskeyword< formatprg< comments< commentstring< formatoptions<'

command -buffer ReloadBeancountCompletions w | lua require'aldur.beancount'.reload_beancount_completions()

lua<<EOF
-- https://github.com/polarmutex/neovim-flake/blob/main/pkgs/polar-init-config/ftplugin/beancount.lua
vim.keymap.set({"n", "v"}, "<Leader>mc", ":s/txn/*/gc<CR>", {
    desc = "beancount-nvim: mark transactions as reconciled",
    noremap = true,
    silent = true,
})
EOF
