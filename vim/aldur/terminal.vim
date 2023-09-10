" Terminal Function
" https://www.reddit.com/r/vim/comments/8n5bzs/using_neovim_is_there_a_way_to_display_a_terminal/

" There wil be a fresh terminal buffer per tab.

let t:aldur_terminal_termbuf = 0
let t:aldur_terminal_termbuf_id = -2
let t:aldur_terminal_term_win = 0

" This can be overriden per tab by `t:term_height_percentage`.
let g:aldur#terminal#term_height_percentage = 0.60

" An optional argument, if true will do (1 - height), in percentage.
function! aldur#terminal#toggle(...) abort
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

        if a:0 > 0 && a:1
            let l:term_height_percentage = 0 - l:term_height_percentage
        endif

        exec 'resize ' . string(&lines * l:term_height_percentage)
        try
            exec 'buffer ' . t:aldur_terminal_termbuf
        catch
            let t:aldur_terminal_termbuf_id = termopen(&shell, {'detach': 0, 'cwd': l:project_root})
            let t:aldur_terminal_termbuf = bufnr('')
        endtry
        let t:aldur_terminal_term_win = win_getid()

        setlocal nobuflisted
        setlocal noswapfile

        startinsert
    endif
endfunction
