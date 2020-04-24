setlocal spell spelllang=en,it textwidth=80 conceallevel=0

let b:ale_linters = ['mdl', ]
let b:ale_fixers = ['prettier', ]

" Polyglot includes this: https://github.com/plasticboy/vim-markdown
" {{{
let g:vim_markdown_no_default_key_mappings = 1
let g:vim_markdown_frontmatter = 1  " Highlight YAML front matter.
let g:vim_markdown_folding_disabled = 1  " Disable folding
let g:vim_markdown_strikethrough = 1  " Enable strikethrough with double tilde
" let g:vim_markdown_conceal = 0  " Disable syntax concealing.
" let g:vim_markdown_conceal_code_blocks = 0  " Disable code blocks concealing.
" }}}
