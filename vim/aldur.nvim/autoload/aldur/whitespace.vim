function! aldur#whitespace#strip_trailing() abort
    call aldur#stay#stay('keepjumps keeppatterns %s/\s\+$//ei')
endfunction

function! aldur#whitespace#retab() abort
    call aldur#stay#stay('silent! undojoin | keepjumps keeppatterns retab!')
endfunction

function! aldur#whitespace#settab(tabsize) abort
    let &l:tabstop = a:tabsize
    let &l:softtabstop = a:tabsize
    let &l:shiftwidth = a:tabsize
    setlocal expandtab
endfunction
