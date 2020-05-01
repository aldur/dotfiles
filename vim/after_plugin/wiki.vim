" Insert YAML front matter and header/title
function! InsertYamlFrontMatterAndHeader() abort
    if exists('g:snips_author')
        let l:author = g:snips_author
    else
        let l:author = 'Adriano Di Luzio'
    end
    execute "normal ggi---\<cr>author: " . l:author . "\<cr>" .
                \ "date: \<C-r>=strftime('%Y-%m-%d %H:%M')\<cr>\<cr>" .
                \ "tags:\<cr>---\<cr>\<cr># " .
                \ expand('%:t:r') ."\<cr>\<esc>"
endfunc

if exists('g:wiki_root')
    " If the full path of this file matches the full `g:wiki_root`:
    execute 'autocmd vimrc BufNewFile ' . expand(g:wiki_root) . '/*.md call InsertYamlFrontMatterAndHeader()'
endif

if exists(':NV')
    nnoremap <silent> <leader>n :NV<CR>
else
    nmap <silent> <leader>n <plug>(wiki-fzf-pages)
endif
nmap <silent> <leader>wt <plug>(wiki-fzf-tags)
