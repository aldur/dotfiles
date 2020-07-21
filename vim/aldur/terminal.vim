" Terminal Function
" https://www.reddit.com/r/vim/comments/8n5bzs/using_neovim_is_there_a_way_to_display_a_terminal/

let g:aldur#terminal#term_buf = 0
let g:aldur#terminal#term_win = 0
let g:aldur#terminal#term_height = 15

function! aldur#terminal#toggle() abort
    if !has('nvim')
        return v:false
    endif

    if win_gotoid(g:aldur#terminal#term_win)
        hide
    else
        botright new
        exec 'resize ' . g:aldur#terminal#term_height
        try
            exec 'buffer ' . g:aldur#terminal#term_buf
        catch
            call termopen(&shell, {'detach': 0})
            let g:aldur#terminal#term_buf = bufnr('')
        endtry
        let g:aldur#terminal#term_win = win_getid()
        setlocal nobuflisted
        startinsert

    endif
endfunction
