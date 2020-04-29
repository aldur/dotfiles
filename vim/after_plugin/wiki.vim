" Insert YAML front matter and header/title, requires UltiSnips.
function! s:InsertYamlFrontMatterAndHeader() abort
  if line('$') == 1 && getline(1) ==# ''
      execute "normal ggi---\<cr>author: Adriano Di Luzio\<cr>date: datetime\<c-j>\<cr>tags:\<cr>---\<cr>\<cr># " . expand('%:t:r') ."\<cr>\<esc>"
  endif
endfunc

autocmd vimrc User WikiLinkOpened call <SID>InsertYamlFrontMatterAndHeader()

function! s:LocalWikiJournal() abort
  execute 'WikiJournal'
  call <SID>InsertYamlFrontMatterAndHeader()
endfunc

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

noremap <silent> <leader>w<leader>w :<C-u>call <SID>LocalWikiJournal()<CR>

nmap <silent> <leader>n <plug>(wiki-fzf-pages)
nmap <silent> <leader>wt <plug>(wiki-fzf-tags)
