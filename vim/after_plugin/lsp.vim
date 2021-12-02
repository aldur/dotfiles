" This must run after the client has been initialized.
lua << EOF
-- FIXME: This doesn't work at the moment because this plugin is run _before_ the GUI sets the font.
if require('plugins.utils').is_nerdfont() then
    local signs = {
        Error = " ",
        Warning = " ",
        Hint = " ",
        Information = " "
    }

    for type, icon in pairs(signs) do
        -- https://github.com/neovim/nvim-lspconfig/wiki/UI-Customization#change-diagnostic-symbols-in-the-sign-column-gutter
        local hl = "DiagnosticSign" .. type
        vim.fn.sign_define(hl, {text = icon, texthl = hl, numhl = hl})
    end
end
EOF
