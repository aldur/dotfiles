call aldur#wiki#bg_check_has_mermaid()

command! -buffer -range=% -nargs=* WikiExportHTML
            \ call aldur#wiki#export_to_html(<line1>, <line2>, <f-args>)
nnoremap <silent><buffer> <leader>wp :WikiExportHTML<CR>
xnoremap <silent><buffer> <leader>wp :WikiExportHTML<CR>

" Faster rename
nnoremap <silent><buffer> <leader>wr :call aldur#wiki#rename_no_ask()<CR>
" Overwrite default command
command! -buffer WikiPageRename         call aldur#wiki#rename_no_ask()

" This prevents LSP clients from overriding this.
setlocal omnifunc=wiki#complete#omnicomplete

nmap <silent><buffer> gx <plug>(wiki-link-follow)
nmap <silent><buffer> gf <plug>(wiki-link-follow)
nmap <silent><buffer> ge <plug>(wiki-link-follow)
