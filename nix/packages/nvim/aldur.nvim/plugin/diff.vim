set diffopt+=iwhite
set fillchars+=diff:\ ,
" set diffopt+=linematch:60

augroup diff_no_treesitter_mappings
    autocmd!
    autocmd FileType diff
                \ silent! nunmap <buffer><silent> ]c |
                \ silent! nunmap <buffer><silent> [c
augroup END
