if has('nvim')
    lua require('plugins/lspconfig')  -- Side effects, autocmds

    " Inspired by how lightline.vim refreshes the statusline.
    autocmd vimrc DiagnosticChanged *
                \ call lightline#update()

    lua require('plugins/utils').configure_signs()

    command! Hover lua vim.lsp.buf.hover()
    command! Rename lua vim.lsp.buf.rename()
    command! CodeActions lua vim.lsp.buf.code_actions()

    command! ToggleVirtualText call aldur#lsp#toggle_virtual_text()
    command! ToggleSigns call aldur#lsp#toggle_signs()
    command! ToggleUpdateInInsert call aldur#lsp#toggle_update_in_insert()
endif
