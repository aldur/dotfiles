local M = {}

function M.is_nerdfont()
    -- If there's a Nerd Font set, display fancy icons.
    local guifont = vim.opt.guifont:get()
    return #guifont == 1 and guifont[1]:lower():find('nerd', 0, true) ~= nil
end

function M.buffer_options_default(bufnr, name, default)
    local ok, result = pcall(vim.api.nvim_buf_get_var, bufnr, name)
    -- If not set, rely on the default value.
    if not ok then return default end
    return result
end

return M
