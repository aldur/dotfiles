" Original source:
" https://github.com/kutsan/dotfiles/blob/8b243cd065b90b3d05dbbc71392f1dba1282d777/.vim/autoload/kutsan/mappings.vim#L1-L52
" function! aldur#terminal#toggle() abort
"     if !has('nvim')
"         return v:false
"     endif

"     if !exists('g:terminal')
"         let g:terminal = {
"             \ 'loaded': v:null,
"             \ 'termbufferid': v:null,
"             \ 'originbufferid': v:null
"         \ }
"     endif

"     function! g:terminal.on_exit(jobid, data, event)
"         silent execute 'buffer' g:terminal.originbufferid
"         silent execute 'bdelete!' g:terminal.termbufferid

"         let g:terminal = {
"             \ 'loaded': v:null,
"             \ 'termbufferid': v:null,
"             \ 'originbufferid': v:null
"         \ }
"     endfunction

"     " Create terminal and finish.
"     if !g:terminal.loaded
"         let g:terminal.originbufferid = bufnr('')

"         enew | call termopen(&shell, g:terminal)
"         let g:terminal.loaded = v:true
"         let g:terminal.termbufferid = bufnr('')

"         return v:true
"     endif

"     if g:terminal.termbufferid ==# bufnr('')
"         " Go back to origin buffer if current buffer is terminal.
"         silent execute 'buffer' g:terminal.originbufferid
"     else
"         " Launch terminal buffer
"         let g:terminal.originbufferid = bufnr('')
"         silent execute 'buffer' g:terminal.termbufferid
"     endif
" endfunction

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
