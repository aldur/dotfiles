let g:neovide_input_use_logo=v:true
let g:neovide_remember_window_size=v:true
let g:neovide_cursor_animation_length=0.02
let g:neovide_cursor_trail_length=0.01

nnoremap <D-w> :bd<cr>

" Integration with macOS clipboard
" https://github.com/neovide/neovide/issues/113#issuecomment-826091133
nmap <D-c> "+y
vmap <D-c> "+y
nmap <D-v> "+p
inoremap <D-v> <c-r>+
cnoremap <D-v> <c-r>+
tnoremap <D-v> '<C-\><C-N>"+pi'

nnoremap <C-6> <C-^>

