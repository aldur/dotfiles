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
