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
let b:pear_tree_did_markdown_ftplugin = 1
let b:pear_tree_pairs = extend(deepcopy(g:pear_tree_pairs), {
            \ '`': {'closer': '`'},
            \ '```': {'closer': '```'}
            \ }, 'keep')
call remove(b:pear_tree_pairs, '[')
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

" NOTE: This overrides a `vim` mapping, see :h gr
nnoremap <buffer><silent> gr :LinkConvertSingle<cr>
xnoremap <buffer><silent> gr :LinkConvertRange<cr>

" Make it so that if you are on a header, you will decrease its level, otherwise open `NvimTreeOpen`
nnoremap <silent><buffer><expr> - tinymd#get_current_header_level() > -1 ? ':call tinymd#decrease_header_level()<cr>' : ':NvimTreeOpen<cr>'
