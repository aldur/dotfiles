function! aldur#whitespace#strip_trailing() abort
    " Preparation: save cursor position
    " (last search is automatically saved because inside a function)
    let l:save = winsaveview()

    " Do the business.
    " vint: -ProhibitCommandRelyOnUser -ProhibitCommandWithUnintendedSideEffect
    execute 'keepjumps keeppatterns %s/\s\+$//ei'

    " Clean up: restore cursor position.
    " vint: +ProhibitCommandRelyOnUser +ProhibitCommandWithUnintendedSideEffect
    call winrestview(l:save)
endfunction

function! aldur#whitespace#retab() abort
    " Preparation: save cursor position
    " (last search is automatically saved because inside a function)
    let l:save = winsaveview()

    " Do the business.
    execute 'keepjumps keeppatterns retab!'

    " Clean up: restore cursor position.
    call winrestview(l:save)
endfunction

