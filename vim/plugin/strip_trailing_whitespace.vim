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

autocmd vimrc FileType c,cpp,java,php,javascript,python,twig,xml,yaml,vim,lua
            \ autocmd vimrc BufWritePre <buffer> call StripTrailingWhitespace()
