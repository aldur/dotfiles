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

    let b:show_signs = !l:lsp_signs
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

function aldur#lsp#toggle_underline() abort
    let l:lsp_underline_enabled = v:lua.require('plugins/lspconfig').underline_enabled(bufnr("%"))

    if !l:lsp_underline_enabled
        call v:lua.info_message("Enabling underline.")
    else
        call v:lua.info_message("Disabling underline.")
    endif

    let b:show_diagnostic_underline = !l:lsp_underline_enabled
    lua require('plugins/lspconfig').reload_config()
endfunction
