function aldur#netrw#open_link_or_file() abort
    let l:to_open = ""
    let l:try_file = expand('<cfile>')

    " Try as absolute path.
    if filereadable(l:try_file)
        let l:to_open = l:try_file
    else
        " Try as relative path
        let l:try_file_with_path = fnamemodify(expand('%:p:h'), ':p') . l:try_file
        if filereadable(l:try_file_with_path)
            let l:to_open = l:try_file_with_path
        endif
    endif

    if l:to_open ==# "" && match(l:try_file, 'https*://') == 0
        let l:to_open = l:try_file
    endif

    if l:to_open ==# ""
        let l:to_open = expand("<cWORD>")
    endif

    let l:to_open = trim(l:to_open)

    lua vim.ui.open(shellescape(l:to_open, 1))
endfunction
