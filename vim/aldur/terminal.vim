" Terminal Function
" https://www.reddit.com/r/vim/comments/8n5bzs/using_neovim_is_there_a_way_to_display_a_terminal/

" There wil be a fresh terminal buffer per tab.

let t:aldur_terminal_termbuf = 0
let t:aldur_terminal_termbuf_id = -2
let t:aldur_terminal_term_win = 0

" This can be overriden per tab by `t:term_height_percentage`.
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
        let l:term_height_percentage = get(t:,
                    \ 'term_height_percentage',
                    \ g:aldur#terminal#term_height_percentage)
        exec 'resize ' . string(&lines * l:term_height_percentage)
        try
            exec 'buffer ' . t:aldur_terminal_termbuf
        catch
            let t:aldur_terminal_termbuf_id = termopen(&shell, {'detach': 0, 'cwd': l:project_root})
            let t:aldur_terminal_termbuf = bufnr('')
        endtry
        let t:aldur_terminal_term_win = win_getid()
        setlocal nobuflisted
        startinsert

    endif
endfunction
