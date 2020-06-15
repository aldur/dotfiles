" At the start of the line or when there's only whitespace triggers tab.
function! aldur#deoplete#check_back_space() abort
    let l:col = col('.') - 1
    return !l:col || getline('.')[l:col - 1]  =~? '\s'
endfunction

function! aldur#deoplete#tab_imap() abort
    if pumvisible()
        " If the completion menu is visible.
        return "\<C-n>"
    elseif aldur#deoplete#check_back_space()
        " If we are at the start of the line / whitespace only
        return "\<TAB>"
    endif

    return deoplete#manual_complete()
endfunction
