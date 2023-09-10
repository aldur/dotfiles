let g:terminal_color_1  = '#232628'
let g:terminal_color_1  = '#fc4384'
let g:terminal_color_2  = '#b3e33b'
let g:terminal_color_3  = '#ebdf86'
let g:terminal_color_4  = '#268ad2'
let g:terminal_color_5  = '#bc99ff'
let g:terminal_color_6  = '#75dff2'
let g:terminal_color_7  = '#f9f9f4'
let g:terminal_color_8  = '#232628'
let g:terminal_color_9  = '#fc4384'
let g:terminal_color_10 = '#b3e33b'
let g:terminal_color_11 = '#ebdf86'
let g:terminal_color_12 = '#268ad1'
let g:terminal_color_13 = '#bc99ff'
let g:terminal_color_14 = '#75dff2'
let g:terminal_color_15 = '#feffff'

if has('nvim')
    " https://github.com/junegunn/fzf.vim/issues/544
    " FZF uses Escape keys to close the window
    autocmd vimrc TermOpen *
                \ setlocal nonumber norelativenumber |
                \ tnoremap <buffer> <Esc><Esc> <c-\><c-n> |
                \ nnoremap <silent><buffer> <leader><space> :<c-U>Files<CR> |
                \ nnoremap <silent><buffer> <leader>bd :<c-U>bdelete!<CR>
    autocmd vimrc FileType fzf tunmap <buffer> <Esc><Esc>

    " Lower the timeout because of the `<Esc><Esc>` quirk.
    " This resets `timeoutlen` to default when leaving.
    autocmd vimrc TermEnter *
                \ let s:timeoutlen = &timeoutlen |
                \ let &timeoutlen = 200
    autocmd vimrc TermLeave *
                \ let &timeoutlen = s:timeoutlen
endif

nnoremap <silent> <C-z> :<C-U>call aldur#terminal#toggle()<CR>
tnoremap <silent> <C-z> <c-\><c-n>:<C-U>call aldur#terminal#toggle()<CR>

" Reset the terminal (close, re-open)
tnoremap <silent> <leader>cd <c-\><c-n>:<C-U>bd! %<bar>call aldur#terminal#toggle()<CR>

" nnoremap <silent> <C-w>t :<C-U>vsplit <bar> terminal<CR>:startinsert<CR>
