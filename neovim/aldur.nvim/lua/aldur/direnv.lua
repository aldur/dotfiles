local M = {}

M.previous_shell = nil

function M.toggle_shell()
    if M.previous_shell == nil then
        _G.info_message("Enabling direnv shell...")
        M.previous_shell = vim.w.shell
        vim.w.shell = vim.env.DIRENVSHELL
        vim.w.direnv_shell = true
    else
        _G.info_message("Disabling direnv shell...")
        vim.w.shell = M.previous_shell
        M.previous_shell = nil
        vim.w.direnv_shell = false
    end
end

function M.shell_is_enabled()
    if vim.w.direnv_shell then return false end
    return vim.w.direnv_shell
end

return M
