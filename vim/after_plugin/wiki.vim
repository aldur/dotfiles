" Insert YAML front matter, requires UltiSnips.
function! InsertYamlFrontMatter()
  if line('$') == 1 && getline(1) ==# ''
      execute "normal ggi---\<cr>title: " . expand('%:t') . "\<cr>author: Adriano Di Luzio\<cr>date: date\<c-j>\<cr>tags:\<cr>---\<cr>\<cr>\<esc>"
  endif
endfunc

autocmd vimrc BufRead,BufNewFile *.wiki setfiletype markdown
autocmd vimrc User WikiLinkOpened call InsertYamlFrontMatter()

" Insert the current date, requires UltiSnips.
function! InsertDate()
  if line('$') == 1 && getline(1) ==# ''
    call InsertYamlFrontMatter()
    execute "normal ggi# datetime\<c-j>\<cr>\<cr>\<esc>"
  endif
endfunc

func! LocalWikiJournal()
  exec 'WikiJournal'
  call InsertDate()
endfunc

nmap <silent> <leader>w<leader>w :<C-u>call LocalWikiJournal()<CR>

nmap <silent> <leader>n <plug>(wiki-fzf-pages)
nmap <silent> <leader>wt <plug>(wiki-fzf-tags)
