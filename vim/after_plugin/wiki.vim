if exists('g:wiki_root')
    " If the full path of this file matches the full `g:wiki_root`:
    execute 'autocmd vimrc BufNewFile ' . expand(g:wiki_root) . '/*.md call aldur#wiki#yaml_frontmatter_and_header()'
endif

if exists(':NV')
    nnoremap <silent> <leader>n :NV<CR>
else
    nmap <silent> <leader>n <plug>(wiki-fzf-pages)
endif
nnoremap <expr><silent><leader>wt ':e ' . g:wiki_root . '/Tasklist.md <CR>'

" This mapping will recursively search for notes, remove the "Notes" folder
" path and remove the `.md` extension.
" Note that this replaces *i_CTRL-X_CTRL-N*
inoremap <expr> <plug>(fzf-complete-note)      fzf#vim#complete#path("find " . expand(g:wiki_root) . " -type f -print \| sed 's#^" . expand(g:wiki_root) . "/##' \| sed 's#." . g:wiki_link_target_type . "$##'")
imap <silent> <c-x><c-n> <plug>(fzf-complete-note)

" Faster rename
nnoremap <silent><buffer> <leader>wr :call aldur#wiki#rename_no_ask()<CR>
