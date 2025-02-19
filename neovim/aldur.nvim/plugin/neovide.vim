if !exists('g:neovide')
    finish
endif

lua vim.o.guifont = "FiraCode Nerd Font:h12"

let g:neovide_remember_window_size = v:true
let g:neovide_hide_mouse_when_typing = v:false
let g:neovide_input_macos_option_key_is_meta = 'only_left'

nnoremap <D-w> :bd<cr>

nnoremap <C-6> <C-^>

lua require('aldur.neovide')

let g:neovide_scale_factor=1.0
function! ChangeScaleFactor(delta) abort
    let g:neovide_scale_factor = g:neovide_scale_factor * a:delta
endfunction
nnoremap <expr><D-=> ChangeScaleFactor(1.1)
nnoremap <expr><D--> ChangeScaleFactor(1/1.1)

let g:neovide_transparency=1.0
let g:neovide_transparency_point=0.1

let g:neovide_floating_shadow = v:false

" let g:neovide_transparency = 0.0
" let g:transparency = 0.8
" let g:neovide_background_color = '#00000000'.printf('%x', float2nr(255 * g:transparency))
