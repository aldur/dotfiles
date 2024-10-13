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
