local M = {}

function M.snippets_path()
    for _, value in ipairs(vim.api.nvim_list_runtime_paths()) do
        if value:match("aldur%.nvim$") then return value .. "/snippets" end
    end
    print("Error: Could not find snippets path!")
    return nil
end

return M
