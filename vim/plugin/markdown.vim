" {{{
let g:vim_markdown_frontmatter = 1  " Highlight YAML front matter.
let g:vim_markdown_strikethrough = 1  " Enable strikethrough with double tilde
let g:vim_markdown_math = 0  " Latex syntax highlight

let g:vim_markdown_auto_insert_bullets = 1  " Automatically insert bullets in Markdown

let g:vim_markdown_follow_anchor = 1  " Open anchored links with `ge`
let g:vim_markdown_no_extensions_in_markdown = 1  " Open links (without extensions) with `ge`

let g:vim_markdown_folding_disabled = 1  " Disable folding
let g:vim_markdown_conceal = 1  " Disable syntax concealing.
let g:vim_markdown_conceal_code_blocks = 1  " Disable code blocks concealing.

" Disable some of the default mappigns
map <Plug> <Plug>Markdown_MoveToParentHeader
map <Plug> <Plug>Markdown_MoveToCurHeader
map <Plug> <Plug>Markdown_MoveToPreviousHeader
map <Plug> <Plug>Markdown_MoveToNextHeader
" }}}
