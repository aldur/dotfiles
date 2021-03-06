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

" Documentation for the `fzf` options is here:
" https://github.com/junegunn/fzf/blob/master/README-VIM.md

" Based on `:h fzf-vim-example-advanced-ripgrep-integration`
"
" We need to show colum and line-number for the preview to work.
" Then, we remove them through `--with-nth=1,4..`
"
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
" This, however, prevents you from excluding paths from the search with
" `!path`.
" let s:rg_default_options = '--delimiter : --nth 4..'
let s:rg_default_options = ''

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

function! aldur#fzf#rg_cd(query, fullscreen) abort
    let l:initial_command = s:rg_default_command . "''"
    let l:spec = {'options': s:rg_default_options, 'dir': a:query}
    call fzf#vim#grep(l:initial_command, 1, fzf#vim#with_preview(l:spec), a:fullscreen)
endfunction


" Inspired by https://github.com/stsewd/dotfiles/blob/7a9a8972c8a994abf42d87814980dc92cdce9a22/config/nvim/init.vim#L419-L434
function! aldur#fzf#open_branch_fzf(line)
    let l:branch = a:line

    " TODO: execute this into the tab terminal buffer if it exists.
    " https://thoughtbot.com/upcase/videos/neovim-sending-commands-to-a-terminal-buffer
    execute 'split | resize 10 | terminal git checkout ' . l:branch

    call feedkeys('i', 'n')
endfunction


function! aldur#fzf#git_checkout_branch(query, fullscreen) abort
    let l:current = system('git symbolic-ref --short HEAD')
    let l:current = substitute(l:current, '\n', '', 'g')
    let l:current_escaped = substitute(l:current, '/', '\\/', 'g')

    let l:source = 'git branch -r --no-color --sort=-committerdate '
                \ . "| sed -r -e 's/^[^/]*\\///' -e '/^"
                \ . l:current_escaped . "$/d' -e '/^HEAD/d'"

    call fzf#vim#grep(
                \ l:source, a:fullscreen,
                \ {
                \     'sink': function('aldur#fzf#open_branch_fzf'),
                \     'options': ['--no-multi', '--header='.l:current],
                \     'dir': aldur#find_root#find_root()
                \ })
endfunction
