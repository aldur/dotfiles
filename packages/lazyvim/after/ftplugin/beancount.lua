-- Buffer-local, like the options below: a global map would shadow the
-- `mc` mark motion in every other buffer.
vim.keymap.set({ "n", "v" }, "mc", ":s/[!?]/*/c<CR>", {
	desc = "beancount: mark transactions as reconciled",
	buffer = true,
	noremap = true,
	silent = true,
})

vim.opt_local.commentstring = "; %s"
-- `gq` reads 'comments', not 'commentstring'. Without this entry the
-- filetype keeps the C-style default, so `gq` drops the `;` leader on
-- wrapped lines.
vim.opt_local.comments = ":;"
-- Account names are colon-separated, so `w`, `*` and `iw` should treat
-- `Assets:Cash` as one word. Buffer-local: the global option would skip the
-- buffer this ftplugin fired for and follow into every later one.
vim.opt_local.iskeyword:append({ ":" })
