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
" The `l` disables formatting of long lines that were there before insert mode starts
" The `n` makes formatting recognize numbered lists. `formatlistpat` complements this option.
"
" The `q` inserts the comment leader with `gq`, but this prevents formatting
" long list elements (since it inserts the leader after breaking the line).
" Disabled it for now.
setlocal formatoptions+=rtln formatoptions-=o formatoptions-=c formatoptions-=q

" This pattern is used by the `n` flag in the `formatoptions`
" - ^\s*\d+\.\s\+ matches a digit followed by a literal period and white space
"   and preceded by white space.
" ^\s[-*+]\s+ matches the list markers followed or preceded by white space.
" ^\[^\ze[^\]]+]:
setlocal formatlistpat=^\\s*\\d\\+\\.\\s\\+\\\|^\\s*[-*+]\\s\\+\\\|^\\[^\\ze[^\\]]\\+\\]:
