function aldur#lsp#toggle_virtual_text() abort
    let l:lsp_vt = v:lua.require('plugins/lspconfig').virtual_text_enabled(bufnr("%"))

    if l:lsp_vt
        call v:lua.info_message("Disabling virtual text.")
    else
        call v:lua.info_message("Enabling virtual text.")
    endif

    let b:show_virtual_text = !l:lsp_vt
    lua require('plugins/lspconfig').reload_config()
endfunction

function aldur#lsp#toggle_signs() abort
    let l:lsp_signs = v:lua.require('plugins/lspconfig').signs_enabled(bufnr("%"))

    if !l:lsp_signs
        call v:lua.info_message("Enabling signs.")
    else
        call v:lua.info_message("Disabling signs.")
    endif

    let b:show_signs = !b:lsp_signs
    lua require('plugins/lspconfig').reload_config()
endfunction

function aldur#lsp#toggle_update_in_insert() abort
    let l:lsp_uii = v:lua.require('plugins/lspconfig').update_in_insert_enabled(bufnr("%"))

    if !l:lsp_uii
        call v:lua.info_message("Enabling update in insert.")
    else
        call v:lua.info_message("Disabling update in insert.")
    endif

    let b:update_in_insert = !l:lsp_uii
    lua require('plugins/lspconfig').reload_config()
endfunction
