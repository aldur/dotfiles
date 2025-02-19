" Quickly change current working directory to buffer's
nnoremap <silent> <leader>cd :call aldur#find_root#cd_to_root()<CR>
nnoremap <silent> <leader>cl :call aldur#find_root#lcd_to_root()<CR>
nnoremap <silent> <leader>cr :call aldur#find_root#toggle_override_root_with_pwd()<CR>
nnoremap <silent> <leader>cc :lua require'aldur.direnv'.toggle_shell()<CR>

call aldur#abbr#cnoreabbrev("lcd", "lcd %:h")

" Remap VIM 0 to first non-blank character
map 0 ^

" Treat long lines as break lines (useful when moving around in them)
noremap j gj
noremap k gk
noremap gj j
noremap gk k

" Note that this disables `i_CTRL-E`
" Yes, this is emacs style, no shame!
inoremap <C-e> <End>

" Disable highlight when <leader><cr> is pressed
nnoremap <silent> <leader><cr> :noh<cr>

" Toggle paste mode on and off
nnoremap <localleader>pp :setlocal paste!<cr>

" Make Y yank everything from the cursor to the end of the line.
noremap Y y$

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

nnoremap <c-]> g<c-]>
vnoremap <c-]> g<c-]>
nnoremap g<c-]> <c-]>
vnoremap g<c-]> <c-]>

" Do not store maps when jumping around.
nnoremap <silent> } :<C-u>execute "keepjumps norm! " . v:count1 . "}"<CR>
nnoremap <silent> { :<C-u>execute "keepjumps norm! " . v:count1 . "{"<CR>
