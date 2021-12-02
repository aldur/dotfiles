function aldur#lsp#toggle_virtual_text() abort
    if get(b:, 'show_virtual_text', v:true) == v:true
        let b:show_virtual_text = v:false
    else
        let b:show_virtual_text = v:true
    endif
    LspRestart
endfunction

function aldur#lsp#toggle_signs() abort
    if get(b:, 'show_signs', v:false) == v:false
        let b:show_signs = v:true
    else
        let b:show_signs = v:false
    endif
    LspRestart
endfunction
