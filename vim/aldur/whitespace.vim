function! aldur#whitespace#strip_trailing() abort
    call aldur#stay#stay('keepjumps keeppatterns %s/\s\+$//ei')
endfunction

function! aldur#whitespace#retab() abort
    call aldur#stay#stay('keepjumps keeppatterns retab!')
endfunction

