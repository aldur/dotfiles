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

nmap <silent><buffer> gf <plug>(wiki-link-follow)
nmap <silent><buffer> ge <plug>(wiki-link-follow)

" This mapping will recursively search for notes, remove the "Notes" folder
" path and remove the `.md` extension.
" Note that this replaces *i_CTRL-X_CTRL-N*
" Note that this also replaces the mapping from `WikiLinkAdd`,
" because this correctly searches attachments.
" inoremap <silent><buffer> <c-x><c-n> <C-o>:WikiLinkAdd<CR>
inoremap <expr> <plug>(fzf-complete-note)      fzf#vim#complete#path($FZF_DEFAULT_COMMAND . " --search-path " . g:wiki_root . " \| sed 's#^" . g:wiki_root . "/##' \| sed 's#.md$##'")
imap <silent><buffer> <c-x><c-n> <plug>(fzf-complete-note)

" NOTE: This overrides a `vim` mapping, see :h gr
nnoremap <buffer><silent> gr :LinkConvertSingle<cr>
xnoremap <buffer><silent> gr :LinkConvertRange<cr>
