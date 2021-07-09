function! aldur#lsp#go_to_definition_or_tag() abort
    let l:clients = luaeval('vim.tbl_keys(vim.lsp.buf_get_clients())')
    if !empty(l:clients)
        lua vim.lsp.buf.definition()
        return
    endif

    tjump
endfunction
