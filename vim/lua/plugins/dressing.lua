require("dressing").setup({
    input = {
        enabled = true,
        mappings = {
            n = {["<Esc>"] = "Close", ["<CR>"] = "Confirm"},
            i = {
                ["<C-c>"] = "Close",
                ["<CR>"] = "Confirm",
                ["<Up>"] = "HistoryPrev",
                ["<Down>"] = "HistoryNext"
            }
        }
    },
    select = {enabled = true, backend = {"fzf", "builtin"}}
})
