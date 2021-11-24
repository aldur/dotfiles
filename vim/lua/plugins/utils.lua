local M = {}

function M.is_nerdfont()
    -- If there's a Nerd Font set, display fancy icons.
    local guifont = vim.opt.guifont:get()
    return #guifont == 1 and guifont[1]:lower():find('nerd', 0, true) ~= nil
end

return M
