function! StripTrailingWhitespace() abort
    " Preparation: save cursor position
    " (last search is automatically saved because inside a function)
    let l:search = @/
    let l:save = winsaveview()

    " Do the business.
    " vint: -ProhibitCommandRelyOnUser -ProhibitCommandWithUnintendedSideEffect
    %s/\s\+$//ei

    " Clean up: restore cursor position.
    " vint: +ProhibitCommandRelyOnUser +ProhibitCommandWithUnintendedSideEffect
    let @/=l:search
    call winrestview(l:save)
endfunction

function! Retab() abort
    " Preparation: save cursor position
    " (last search is automatically saved because inside a function)
    let l:save = winsaveview()

    " Do the business.
    retab!

    " Clean up: restore cursor position.
    call winrestview(l:save)
endfunction

autocmd vimrc FileType c,cpp,java,php,javascript,markdown,python,twig,xml,yaml,vim,lua
            \ autocmd vimrc BufWritePre <buffer> call StripTrailingWhitespace()

autocmd vimrc FileType markdown
            \ autocmd vimrc BufWritePre <buffer> call Retab()
