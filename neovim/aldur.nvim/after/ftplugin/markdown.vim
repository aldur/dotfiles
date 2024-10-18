setlocal spell spelllang=en,it
setlocal textwidth=80
setlocal conceallevel=0
setlocal nojoinspaces
call aldur#whitespace#settab(2)

" Allow reading modelines in YAML header
setlocal modelines=5

" Match fenced code blocks and inline backticks.
let b:match_words = '```.\+:```$,\S\@<!`:`\S\@!'

let b:surround_103 = "**\r**"  " g - bold
let b:surround_105 = "_\r_"  " i - italic

" Disable three backticks disappearing on new-line
let b:pear_tree_repeatable_expand = 0

" Disable pairs for [, instead rely on snippets.
if has_key(b:pear_tree_pairs, '[')
    call remove(b:pear_tree_pairs, '[')
endif
let b:pear_tree_pairs['_'] = {'closer': '_'}
let b:pear_tree_pairs['*'] = {'closer': '*'}

nnoremap <silent><buffer> gO :<c-U>BLines ^#<CR>

iabbrev <buffer> e' è
iabbrev <buffer> cioe' cioè
iabbrev <buffer> c'e' c'è
iabbrev <buffer> pero' però
iabbrev <buffer> perche' perché
iabbrev <buffer> poiche' poiché
iabbrev <buffer> finche' finché
iabbrev <buffer> piu' più
iabbrev <buffer> puo' può
iabbrev <buffer> gia' già
iabbrev <buffer> -> →
iabbrev <buffer> <- ←
iabbrev <buffer> <-> ↔

setlocal foldmethod=expr
setlocal foldexpr=nvim_treesitter#foldexpr()
setlocal nofoldenable
setlocal foldnestmax=5
setlocal foldminlines=1
