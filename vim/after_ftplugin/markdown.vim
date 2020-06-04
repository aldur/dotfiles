scriptencoding utf-8

setlocal spell spelllang=en,it
setlocal textwidth=80
setlocal conceallevel=0
setlocal nojoinspaces

let b:ale_linters = ['mdl', ]
let b:ale_fixers = ['prettier', ]
" This configures prettier for Markdown even if it says javascript :)
let b:ale_javascript_prettier_options = '--tab-width 4'

" Match fenced code blocks and inline backticks.
let b:match_words = '```.\+:```$,\S\@<!`:`\S\@!'

" Disable three backticks disappearing on new-line
let b:pear_tree_repeatable_expand = 0

nnoremap <silent><buffer> + :<c-U> call aldur#markdown#header_increase()<CR>
nnoremap <silent><buffer> - :<c-U> call aldur#markdown#header_decrease()<CR>
nnoremap <silent><buffer> [` :<c-U> call aldur#markdown#fence_start()<CR>
nnoremap <silent><buffer> ]` :<c-U> call aldur#markdown#fence_end()<CR>

nmap <silent><buffer> [c <Plug>Markdown_MoveToCurHeader
nmap <silent><buffer> [p <Plug>Markdown_MoveToParentHeader

nnoremap <silent><buffer> gO :<c-U>BLines ^#<CR>

iabbrev <buffer> e' è
iabbrev <buffer> cioe' cioè
iabbrev <buffer> c'e' c'è
iabbrev <buffer> perche' perché
iabbrev <buffer> poiche' poiché
iabbrev <buffer> piu' più
iabbrev <buffer> puo' può
iabbrev <buffer> gia' già

