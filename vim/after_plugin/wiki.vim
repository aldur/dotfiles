" Insert YAML front matter and header/title, requires UltiSnips.
function! InsertYamlFrontMatterAndHeader() abort
    execute "normal ggi---\<cr>author: " . g:snips_author . "\<cr>" .
                \ "date: datetime\<C-r>=UltiSnips#ExpandSnippet()\<cr>\<cr>" .
                \ "tags:\<cr>---\<cr>\<cr># " .
                \ expand('%:t:r') ."\<cr>\<esc>"
endfunc

if (exists('g:wiki_root') && exists('g:snips_author'))
    " If the full path of this file matches the full `g:wiki_root`:
    execute 'autocmd vimrc BufNewFile ' . expand(g:wiki_root) . '/*.md call InsertYamlFrontMatterAndHeader()'
endif

function! LocalAddHeaderLevel() abort
    let lnum = line('.')
    let line = getline(lnum)
    let rxHdr = vimwiki#vars#get_syntaxlocal('rxH')
    if line =~# '^\s*$'
        return
    endif

    if line =~# vimwiki#vars#get_syntaxlocal('rxHeader')
        let level = vimwiki#u#count_first_sym(line)
        if level < 6
            if vimwiki#vars#get_syntaxlocal('symH')
                let line = substitute(line, '\('.rxHdr.'\+\).\+\1', rxHdr.'&'.rxHdr, '')
            else
                let line = substitute(line, '\('.rxHdr.'\+\).\+', rxHdr.'&', '')
            endif
            call setline(lnum, line)
        endif
    else
        let line = substitute(line, '^\s*', '&'.rxHdr.' ', '')
        if vimwiki#vars#get_syntaxlocal('symH')
            let line = substitute(line, '\s*$', ' '.rxHdr.'&', '')
        endif
        call setline(lnum, line)
    endif
endfunction

nmap <silent> <leader>n <plug>(wiki-fzf-pages)
nmap <silent> <leader>wt <plug>(wiki-fzf-tags)
