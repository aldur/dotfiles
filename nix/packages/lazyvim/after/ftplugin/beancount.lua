vim.keymap.set({"n", "v"}, "mc", ":s/!/*/c<CR>", {
    desc = "beancount: mark transactions as reconciled",
    noremap = true,
    silent = true,
})

vim.opt_local.commentstring = "; %s"
vim.opt_global.iskeyword:append {":"}
