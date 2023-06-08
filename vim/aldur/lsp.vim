function aldur#lsp#toggle_virtual_text() abort
    let l:lsp_vt = v:lua.require('plugins/lspconfig').virtual_text_enabled(bufnr("%"))

    if l:lsp_vt == v:true
        call v:lua.info_message("Disabling virtual text.")
        let b:show_virtual_text = v:false
    else
        call v:lua.info_message("Enabling virtual text.")
        let b:show_virtual_text = v:true
    endif
    lua require('plugins/lspconfig').reload_config()
endfunction

function aldur#lsp#toggle_signs() abort
    let l:lsp_signs = v:lua.require('plugins/lspconfig').signs_enabled(bufnr("%"))

    if l:lsp_signs == v:false
        call v:lua.info_message("Enabling signs.")
        let b:show_signs = v:true
    else
        call v:lua.info_message("Disabling signs.")
        let b:show_signs = v:false
    endif
    lua require('nvim-lspconfig').reload_config()
endfunction

function aldur#lsp#toggle_update_in_insert() abort
    let l:lsp_uii = v:lua.require('plugins/lspconfig').update_in_insert_enabled(bufnr("%"))

    if l:lsp_uii == v:false
        call v:lua.info_message("Enabling update in insert.")
        let b:update_in_insert = v:true
    else
        call v:lua.info_message("Disabling update in insert.")
        let b:update_in_insert = v:false
    endif
    lua require('nvim-lspconfig').reload_config()
endfunction
