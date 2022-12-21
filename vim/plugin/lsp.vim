if has('nvim')
    lua require('plugins/nvim-lspconfig')

    " Inspired by how lightline.vim refreshes the statusline.
    autocmd vimrc DiagnosticChanged *
                \ call lightline#update() |
                \ lua vim.diagnostic.setloclist({open = false})

    lua require('plugins/trouble')

    command! Hover lua vim.lsp.buf.hover()
    command! Rename lua vim.lsp.buf.rename()
    command! CodeActions lua vim.lsp.buf.code_actions()

    command! ToggleVirtualText call aldur#lsp#toggle_virtual_text()
    command! ToggleSigns call aldur#lsp#toggle_signs()
    command! ToggleUpdateInInsert call aldur#lsp#toggle_update_in_insert()

    " This must run after the GUI has been initialized as it checks for a NERD
    " font. We work around this by calling it with `DiagnosticChanged`, and then
    " having making it a no-op after it executes the first time.
    autocmd vimrc DiagnosticChanged * lua require('plugins/utils').set_nerd_signs()

    autocmd CursorHold * lua require'nvim-lightbulb'.update_lightbulb()
endif
