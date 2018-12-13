set hidden  " Allows to change buffer without saving

" Close the current buffer
nnoremap <leader>bd :bdelete<cr>

" Close all the buffers
nnoremap <leader>ba :%bdelete<cr>

" Specify the behavior when switching between buffers
set switchbuf=useopen,usetab,newtab

" Resize splits when the window is resized
autocmd vimrc VimResized * :wincmd =
