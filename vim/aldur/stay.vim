" Execute a command by preserving the current window view.
" Partial source:
" https://github.com/yangle/dotfiles/blob/ce27e1704be89cbb7f2667162dbd9113155feac9/_vimrc
function! aldur#stay#stay(command) abort
    " let s:pos = getpos('. ')

    " Preparation: save cursor position
    " (last search is automatically saved because inside a function)
    let s:view = winsaveview()

    " Do the business.
    " vint: -ProhibitCommandRelyOnUser -ProhibitCommandWithUnintendedSideEffect
    execute a:command

    " Clean up: restore cursor position.
    " vint: +ProhibitCommandRelyOnUser +ProhibitCommandWithUnintendedSideEffect
    call winrestview(s:view)

    " call setpos('.', s:pos)
endfunc
