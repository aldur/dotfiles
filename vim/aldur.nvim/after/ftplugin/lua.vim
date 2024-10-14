" Same mapping as `vim-dispatch`
" nnoremap <silent><buffer> m<CR> :<C-u>luafile %<CR>
" NOTE: This will only work for `neovim` modules
nnoremap <silent><buffer> m<CR> :<c-u>lua require"aldur.utils".reload_module()<CR>
