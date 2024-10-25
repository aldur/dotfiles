if !exists('g:wiki_root')
    finish
endif

let g:wiki_root = expand(g:wiki_root)

" If the full path of this file matches the full `g:wiki_root`:
lua <<EOF
vim.filetype.add({
    pattern = {
        [vim.g.wiki_root .. ".*%.md"] = 'markdown.wiki'
    },
})
EOF

if exists(':NV')
    nnoremap <silent> <leader>n :NV<CR>
else
    nmap <silent> <leader>n <plug>(wiki-fzf-pages)
endif


