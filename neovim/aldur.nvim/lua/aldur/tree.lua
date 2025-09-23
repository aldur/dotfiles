local M = {}

function M.open_tree_at_root()
    local api = require "nvim-tree.api"
    api.tree.open({
        path = vim.fn['aldur#find_root#find_root'](),
        find_file = true
    })
end

return M
