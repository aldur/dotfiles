local M = {}

M.previous_shell = nil

function M.toggle_shell()
    if M.previous_shell == nil then
        _G.info_message("Enabling direnv shell...")
        -- TODO: Fallback to other shell?
        M.previous_shell = vim.o.shell
        vim.o.shell = vim.env.DIRENVSHELL
        vim.g.direnv_shell = true
    else
        _G.info_message("Disabling direnv shell...")
        vim.o.shell = M.previous_shell
        M.previous_shell = nil
        vim.g.direnv_shell = false
    end
end

function M.shell_is_enabled()
    if vim.g.direnv_shell == nil then return false end
    return vim.g.direnv_shell
end

return M
