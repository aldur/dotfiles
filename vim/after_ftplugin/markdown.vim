scriptencoding utf-8

setlocal spell spelllang=en,it
setlocal textwidth=80
setlocal conceallevel=0
setlocal nojoinspaces

let b:ale_linters = ['mdl', ]
let b:ale_fixers = ['prettier', ]
" This configures prettier for Markdown even if it says javascript :)
let b:ale_javascript_prettier_options = '--tab-width 4'

" Disable three backticks disappearing on new-line
let b:pear_tree_repeatable_expand = 0

nnoremap <silent><buffer> + :<c-U> call HeaderIncrease()<CR>
nnoremap <silent><buffer> - :<c-U> call HeaderDecrease()<CR>

" For Markdown, we enable additional snippets (from ~/.vim/UltiSnips).
" let b:UltiSnipsSnippetDirectories=['UltiSnips']

iabbrev <buffer> e' è
iabbrev <buffer> perche' perché

" TODO: You can do this with `imap`
" iabbrev <buffer> a' à
" iabbrev <buffer> e'' é
" iabbrev <buffer> i' ì
" iabbrev <buffer> o' ò
" iabbrev <buffer> u' ù
