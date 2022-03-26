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

M._nerd_signs_were_set = false
function M.set_nerd_signs()
    if M.is_nerdfont() and M._nerd_signs_were_set == false then
        -- _G.info_message("Setting nerd signs...")
        local signs = {
            Error = "",
            Warning = "",
            Hint = "",
            Info = ""
        }

        for type, icon in pairs(signs) do
            -- https://github.com/neovim/nvim-lspconfig/wiki/
            -- UI-Customization#change-diagnostic-symbols-in-the-sign-column-gutter
            local hl = "DiagnosticSign" .. type
            if vim.fn.sign_define(hl, {text = icon}) ~= 0 then
                _G.warning_message("Couldn't set sign " .. type)
            end
        end
    end
    M._nerd_signs_were_set = true
end

return M
