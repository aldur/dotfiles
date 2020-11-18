" Here we are experimenting with a custom sink.
" To have `query` filled, you will need to pass `--print-query` to FZF.
" To have `keypress` filled, you will need to pass `--expect` to FZF.
function! aldur#fzf#rg_sink(lines)
  if len(a:lines) < 2
    return
  endif

  let query    = a:lines[0]
  let keypress = a:lines[1]

  PPmsg a:lines
endfunction

" Based on `:h fzf-vim-example-advanced-ripgrep-integration`
"
" We need to show colum and line-number for the preview to work.
" Then, we remove them through `--with-nth=1,4..`
"
" Documentation for the `fzf` options is here:
" https://github.com/junegunn/fzf/blob/master/README-VIM.md
function! aldur#fzf#rg_notes(query, fullscreen) abort
    let l:initial_command = "rg --column --line-number --no-heading --color=always ''"
    let l:spec = {'options': '--with-nth=1,4.. --exact --print-query', 'dir': g:wiki_root, 'sink*': function('aldur#fzf#rg_sink')}
    call fzf#vim#grep(l:initial_command, 1, fzf#vim#with_preview(l:spec), a:fullscreen)
endfunction

" Here we don't need --smart-case because we set it in `~/.ripgreprc`.
let s:rg_default_command = 'rg --column --line-number --no-heading --color=always '

" https://github.com/junegunn/fzf.vim/issues/346#issuecomment-288483704
" {'options': '--delimiter : --nth 4..'} will make `rg` search file contents
" only, not names.
let s:rg_default_options = '--delimiter : --nth 4..'

" The `dir` option specify the search directory, source:
" https://github.com/junegunn/fzf.vim/issues/837
"
" If you are wondering how this works, in short when you trigger this without
" any arguments `rg` gets called without any arguments as well and lists all
" file lines. Then, `fzf` does the filtering.
function! aldur#fzf#rg_project(query, fullscreen) abort
    let l:initial_command = s:rg_default_command . shellescape(a:query)
    let l:spec = {'options': s:rg_default_options, 'dir': aldur#find_root#find_root()}
    call fzf#vim#grep(l:initial_command, 1, fzf#vim#with_preview(l:spec), a:fullscreen)
endfunction

" This does not seem to be working:
" https://github.com/junegunn/fzf.vim/issues/1135
function! aldur#fzf#rg_cd(query, fullscreen) abort
    let l:initial_command = s:rg_default_command . "''"
    let l:spec = {'options': s:rg_default_options, 'dir': a:query}
    call fzf#vim#grep(l:initial_command, 1, fzf#vim#with_preview(l:spec), a:fullscreen)
endfunction
