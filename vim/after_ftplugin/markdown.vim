scriptencoding utf-8

setlocal spell spelllang=en,it
setlocal textwidth=80
setlocal conceallevel=0
setlocal nojoinspaces
call aldur#whitespace#settab(2)

" Signs are disabled in LSP configuration.
" setlocal signcolumn=no

" Allow reading modelines in YAML header
setlocal modelines=5

" Disable virtual text.
let b:show_virtual_text = v:false

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

nnoremap <silent><buffer> [` :<c-U>call aldur#markdown#to_fence_start()<CR>
onoremap <silent><buffer> [` :<c-U>call aldur#markdown#to_fence_start()<CR>
vnoremap <silent><buffer> [` <esc>:<C-U>call aldur#markdown#visual_move('aldur#markdown#to_fence_start')<CR>

nnoremap <silent><buffer> ]` :<c-U>call aldur#markdown#to_fence_end()<CR>
onoremap <silent><buffer> ]` :<C-U>call aldur#markdown#to_fence_end()<CR>
vnoremap <silent><buffer> ]` <esc>:<C-U>call aldur#markdown#visual_move('aldur#markdown#to_fence_end')<CR>

nnoremap <silent><buffer> ]] :<C-U>call aldur#markdown#to_next_header()<CR>
onoremap <silent><buffer> ]] :<C-U>call aldur#markdown#to_next_header()<CR>
vnoremap <silent><buffer> ]] <esc>:<C-U>call aldur#markdown#visual_move('aldur#markdown#to_next_header')<CR>

nnoremap <silent><buffer> [[ :<C-U>call aldur#markdown#to_previous_header()<CR>
onoremap <silent><buffer> [[ :<C-U>call aldur#markdown#to_previous_header()<CR>
vnoremap <silent><buffer> [[ <esc>:<C-U>call aldur#markdown#visual_move('aldur#markdown#to_previous_header')<CR>

nnoremap <silent><buffer> [p :<C-U>call aldur#markdown#to_parent_header()<CR>
onoremap <silent><buffer> [p :<C-U>call aldur#markdown#to_parent_header()<CR>
vnoremap <silent><buffer> [p <esc>:<C-U>call aldur#markdown#visual_move('aldur#markdown#to_parent_header')<CR>

nnoremap <silent><buffer> + :<c-U>call aldur#markdown#increase_header_level()<CR>
nnoremap <silent><buffer> - :<c-U>call aldur#markdown#decrease_header_level()<CR>

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

onoremap <silent><buffer> ih :<C-u>call aldur#markdown#header_textobj(v:true)<CR>
onoremap <silent><buffer> ah :<C-u>call aldur#markdown#header_textobj(v:false)<CR>
xnoremap <silent><buffer> ih :<C-u>call aldur#markdown#header_textobj(v:true)<CR>
xnoremap <silent><buffer> ah :<C-u>call aldur#markdown#header_textobj(v:false)<CR>

onoremap <silent><buffer> if :<C-u>call aldur#markdown#fence_textobj(v:true)<CR>
onoremap <silent><buffer> af :<C-u>call aldur#markdown#fence_textobj(v:false)<CR>
xnoremap <silent><buffer> if :<C-u>call aldur#markdown#fence_textobj(v:true)<CR>
xnoremap <silent><buffer> af :<C-u>call aldur#markdown#fence_textobj(v:false)<CR>

setlocal foldmethod=expr
setlocal foldexpr=nvim_treesitter#foldexpr()
setlocal nofoldenable
setlocal foldnestmax=5
setlocal foldminlines=1
