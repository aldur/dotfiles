local function nvim_tree_on_attach(bufnr)
    local api = require "nvim-tree.api"

    vim.api.nvim_create_autocmd('BufDelete', {
        callback = function(state) vim.opt.shada:append(state.file) end
    })

    -- default mappings
    api.config.mappings.default_on_attach(bufnr)

    local function opts(desc)
        return {
            desc = "nvim-tree: " .. desc,
            buffer = bufnr,
            noremap = true,
            silent = true,
            nowait = true
        }
    end

    -- custom mappings
    vim.keymap.set("n", "<C-t>", api.tree.change_root_to_parent, opts("Up"))
    vim.keymap.set("n", "?", api.tree.toggle_help, opts("Help"))
end

require("nvim-tree").setup({
    disable_netrw = true, -- Just to be sure, it is also disabled in `init.vim`.
    on_attach = nvim_tree_on_attach,
    reload_on_bufenter = true,
    diagnostics = {enable = true},
    actions = {change_dir = {enable = false}}
})

vim.keymap.set("n", "-", function()
    local api = require "nvim-tree.api"
    api.tree.open({
        path = vim.fn['aldur#find_root#find_root'](),
        find_file = true
    })
end, {noremap = true, silent = true, desc = "Open nvim-tree with current root."})

require("oil").setup()
