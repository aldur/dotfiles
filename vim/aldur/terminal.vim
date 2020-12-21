" Terminal Function
" https://www.reddit.com/r/vim/comments/8n5bzs/using_neovim_is_there_a_way_to_display_a_terminal/

" The terminal buffer will be shared across windows and tabs.
" The termina _window_, however, will be local to the current window.

let g:aldur#terminal#term_buf = 0
let g:aldur#terminal#term_buf_id = -2
let t:aldur_terminal_term_win = 0
let g:aldur#terminal#term_height_percentage = 0.40

function! aldur#terminal#toggle() abort
    if !has('nvim')
        return v:false
    endif

    let l:project_root = aldur#find_root#find_root()

    if exists('t:aldur_terminal_term_win') && win_gotoid(t:aldur_terminal_term_win)
        hide
    else
        botright new
        exec 'resize ' . string(&lines * g:aldur#terminal#term_height_percentage)
        try
            exec 'buffer ' . g:aldur#terminal#term_buf
        catch
            let g:aldur#terminal#term_buf_id = termopen(&shell, {'detach': 0, 'cwd': l:project_root})
            let g:aldur#terminal#term_buf = bufnr('')
        endtry
        let t:aldur_terminal_term_win = win_getid()
        setlocal nobuflisted
        startinsert

    endif
endfunction
