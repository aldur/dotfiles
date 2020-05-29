function! aldur#ale#fix_gently() abort
    " Preparation: save cursor position
    " (last search is automatically saved because inside a function)
    let l:save = winsaveview()

    " Do the business.
    ALEFix

    " Clean up: restore cursor position.
    call winrestview(l:save)
endfunction
