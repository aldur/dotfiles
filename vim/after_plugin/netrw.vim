" Not an external plugin, but still... :)
let g:netrw_banner = 0  " Disable top banner
let g:netrw_silent = 1  " Do not output `scp` commands etc, while saving.
let g:netrw_browse_split = 0  " Open new files in same window
let g:netrw_altv = 1  " Split to right
let g:netrw_winsize = 25  " Window height/width on split
let g:netrw_liststyle = 3  " Tree style listing

autocmd vimrc FileType netrw setl bufhidden=wipe  " Wipe netrw buffers when hidden

" For some reasons, netrw `gx` seems not to work on recent versions of nvim.
" This fixes it.
" https://stackoverflow.com/questions/9458294/open-url-under-cursor-in-vim-with-browser/53817071#53817071
nnoremap <silent> gx :execute 'silent! !open ' . shellescape(expand('<cWORD>'), 1)<cr>
