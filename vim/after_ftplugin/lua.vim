" Same mapping as `vim-dispatch`
" nnoremap <silent><buffer> m<CR> :<C-u>luafile %<CR>
" NOTE: This will only work for `neovim` packages
nnoremap <silent><buffer> m<CR> :<c-u>lua require"plugins/utils".reload_package()<CR>
