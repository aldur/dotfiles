function aldur#lsp#toggle_virtual_text() abort
    if get(b:, 'show_virtual_text', v:true) == v:true
        call v:lua.info_message("Disabling virtual text.")
        let b:show_virtual_text = v:false
    else
        call v:lua.info_message("Enabling virtual text.")
        let b:show_virtual_text = v:true
    endif
    lua require('plugins/nvim-lspconfig').reload_config()
endfunction

function aldur#lsp#toggle_signs() abort
    if get(b:, 'show_signs', v:false) == v:false
        call v:lua.info_message("Enabling signs.")
        let b:show_signs = v:true
    else
        call v:lua.info_message("Disabling signs.")
        let b:show_signs = v:false
    endif
    lua require('plugins/nvim-lspconfig').reload_config()
endfunction

function aldur#lsp#toggle_update_in_insert() abort
    if get(b:, 'update_in_insert', v:false) == v:false
        call v:lua.info_message("Enabling update in insert.")
        let b:update_in_insert = v:true
    else
        call v:lua.info_message("Disabling update in insert.")
        let b:update_in_insert = v:false
    endif
    lua require('plugins/nvim-lspconfig').reload_config()
endfunction
