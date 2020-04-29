setlocal spell spelllang=en,it
setlocal textwidth=80
setlocal conceallevel=0
setlocal nojoinspaces

let b:ale_linters = ['mdl', ]
let b:ale_fixers = ['prettier', ]
" This configures prettier for Markdown even if it says javascript :)
let b:ale_javascript_prettier_options = '--tab-width 4'

" Polyglot includes this: https://github.com/plasticboy/vim-markdown
" {{{
let g:vim_markdown_no_default_key_mappings = 1
let g:vim_markdown_frontmatter = 1  " Highlight YAML front matter.
let g:vim_markdown_folding_disabled = 1  " Disable folding
let g:vim_markdown_strikethrough = 1  " Enable strikethrough with double tilde
let g:vim_markdown_new_list_item_indent = 2  " When inserting a new list item, indent it by two spaces
let g:vim_markdown_auto_insert_bullets = 1  " Automatically insert bullets in Markdown
" let g:vim_markdown_conceal = 0  " Disable syntax concealing.
" let g:vim_markdown_conceal_code_blocks = 0  " Disable code blocks concealing.
" }}}

nnoremap <silent> <buffer> + :.HeaderIncrease<CR>
nnoremap <silent> <buffer> - :.HeaderDecrease<CR>
