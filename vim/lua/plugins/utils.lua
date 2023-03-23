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

function M.configure_signs()
    -- _G.info_message("Configuring signs...")
    local highlights = {Error = "ErrorMsg", Hint = "MoreMsg", Info = "ModeMsg"}

    for type, hl in pairs(highlights) do
        -- https://github.com/neovim/nvim-lspconfig/wiki/
        -- UI-Customization#change-diagnostic-symbols-in-the-sign-column-gutter
        local sign = "DiagnosticSign" .. type
        if vim.fn.sign_define(sign, {numhl = hl, text = ""}) ~= 0 then
            _G.warning_message("Couldn't set sign " .. type)
        end
    end

    -- "Warn" -> "WarningMsg"
    -- Special treatment
    if vim.fn.sign_define("DiagnosticSignWarn",
                          {numhl = "WarningMsg", text = ""}) ~= 0 then
        _G.warning_message("Couldn't set sign " .. type)
    end
end

return M
