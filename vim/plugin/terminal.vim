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
    autocmd vimrc TermOpen * tnoremap <buffer> <Esc> <c-\><c-n>
    autocmd vimrc FileType fzf tunmap <buffer> <Esc>
endif
