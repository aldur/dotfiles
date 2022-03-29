" Source http://www.itu.dk/people/albo/update/2017/07/22/open-dictionary-from-vim.html
" Call with an empty string argument to define word under cursor.
function aldur#dictionary#dictionary(...) abort
    let word = ''

    if a:1 !=# ''
        let word = a:1
    else
        let word = shellescape(expand('<cword>'))
    endif

    if has('mac') || has('macunix')
        call system("open dict://" . word)
    else
        echoerr "Does not support ~macOS yet."
    endif
endfunction
