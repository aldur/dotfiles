function! aldur#deoplete#check_back_space() abort
    let l:col = col('.') - 1
    return !l:col || getline('.')[l:col - 1]  =~? '\s'
endfunction

