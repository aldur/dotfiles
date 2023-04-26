if !exists('g:neovide')
    finish
endif

lua vim.o.guifont = "FiraCode Nerd Font:h14"

let g:neovide_remember_window_size = v:true
let g:neovide_hide_mouse_when_typing = v:false
let g:neovide_input_macos_alt_is_meta = v:true

nnoremap <D-w> :bd<cr>

nnoremap <C-6> <C-^>

lua << EOF
    vim.g.neovide_input_use_logo = 1 -- enable use of the logo (cmd) key
    vim.keymap.set('v', '<D-c>', '"+y') -- Copy

    vim.keymap.set('n', '<D-v>', '"+P') -- Paste normal mode
    vim.keymap.set('v', '<D-v>', '"+P') -- Paste visual mode
    vim.keymap.set('c', '<D-v>', '<C-R>+') -- Paste command mode
    vim.keymap.set('i', '<D-v>', '<ESC>"+pa') -- Paste insert mode
    -- vim.keymap.set('!', '<D-v>', '<C-R>+')
    vim.keymap.set('t', '<D-v>', '<C-\\><C-O>"+P')
EOF

let g:neovide_scale_factor=1.0
function! ChangeScaleFactor(delta) abort
    let g:neovide_scale_factor = g:neovide_scale_factor * a:delta
endfunction
nnoremap <expr><D-=> ChangeScaleFactor(1.1)
nnoremap <expr><D--> ChangeScaleFactor(1/1.1)

let g:neovide_transparency=1.0
let g:neovide_transparency_point=0.1

" let g:neovide_transparency = 0.0
" let g:transparency = 0.8
" let g:neovide_background_color = '#00000000'.printf('%x', float2nr(255 * g:transparency))
