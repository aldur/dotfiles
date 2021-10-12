let g:neovide_input_use_logo=v:true
let g:neovide_remember_window_size=v:true
let g:neovide_cursor_animation_length=0.05
let g:neovide_cursor_trail_length=0.5

nnoremap <D-w> :bd<cr>

inoremap <D-v> <C-o>"+p
cnoremap <D-v> <C-r>*
tnoremap <D-v> "+p
onoremap <D-v> "+p

vnoremap <D-c> "+y

nnoremap <C-6> <C-^>
