if !exists('g:wiki_root')
    finish
endif

let g:wiki_root = expand(g:wiki_root)

" If the full path of this file matches the full `g:wiki_root`:
execute 'autocmd vimrc BufRead,BufNewFile ' . g:wiki_root . '/*.md set filetype=markdown.wiki'

if exists(':NV')
    nnoremap <silent> <leader>n :NV<CR>
else
    nmap <silent> <leader>n <plug>(wiki-fzf-pages)
endif

" This mapping will recursively search for notes, remove the "Notes" folder
" path and remove the `.md` extension.
" Note that this replaces *i_CTRL-X_CTRL-N*
inoremap <expr> <plug>(fzf-complete-note)      fzf#vim#complete#path("find " . g:wiki_root . " -type f -print \| sed 's#^" . g:wiki_root . "/##' \| sed 's#." . g:wiki_link_target_type . "$##'")
imap <silent> <c-x><c-n> <plug>(fzf-complete-note)
