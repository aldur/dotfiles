" Quickly change current working directory to buffer's
nnoremap <leader>cd :call aldur#find_root#cd_to_root()<CR>

" Remap VIM 0 to first non-blank character
map 0 ^

" Treat long lines as break lines (useful when moving around in them)
noremap j gj
noremap k gk
noremap gj j
noremap gk k

" Disable highlight when <leader><cr> is pressed
nnoremap <silent> <leader><cr> :noh<cr>

" Toggle paste mode on and off
nnoremap <localleader>pp :setlocal paste!<cr>

" Make Y yank everything from the cursor to the end of the line.
noremap Y y$

" Quickly call 'make'
if exists(':Make')
    nnoremap <leader>m :Make<cr>
else
    nnoremap <leader>m :make<cr>
endif

" Use 'c*' to change the word under the cursor, repeat with '.'
nnoremap c* *<C-o>cgn

if &term =~? '^screen'
    " tmux will send xterm-style keys when xterm-keys is on
    execute "set <xUp>=\e[1;*A"
    execute "set <xDown>=\e[1;*B"
    execute "set <xRight>=\e[1;*C"
    execute "set <xLeft>=\e[1;*D"
endif

" Useful mappings for managing tabs
nnoremap <leader>tn :tabnew<cr>
nnoremap <leader>to :tabonly<cr>
nnoremap <leader>tc :tabclose<cr>

" Spell checking
nnoremap <localleader>ss :setlocal spell!<cr>

" Quickly reach for :
nnoremap <leader>; :

" Disable the `co` map
nnoremap co <plug>

" Fugitive maps
nnoremap gdh :diffget //2<CR>
nnoremap gdl :diffget //3<CR>
