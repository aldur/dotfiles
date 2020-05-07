" Note: I have to set these values here because otherwise `vim-markdown` will override them.
" Continue (numbered) lists with what was on previous line.
setlocal comments=
setlocal comments+=b:*\ TODO:,b:-\ TODO:
setlocal comments+=b:*\ [\ ]:,b:-\ [\ ]
setlocal comments+=b:*\ [x]:,b:-\ [x]
setlocal comments+=b:*,b:-,b:1.,b:>
setlocal commentstring=<!--%s-->

" This is `jrtqln` by default:
" The `r` makse sure that a new * is inserted after pressing enter.
" The `t` auto-wraps text.
" The `q` allows formatting with `qg`
" The `l` disables formatting of long lines that were there before insert more starts
" The `n` makes formatting recognize numbered lists. `formatlistpat`
" complements this option.
" setlocal formatoptions+=rtqln formatoptions-=o formatoptions-=c
setlocal formatlistpat=^\\s*\\d\\+\\.\\s\\+\\\|^[-*+]\\s\\+\\\|^\\[^\\ze[^\\]]\\+\\]:
