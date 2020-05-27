" {{{
let g:vim_markdown_frontmatter = 1  " Highlight YAML front matter.
let g:vim_markdown_strikethrough = 1  " Enable strikethrough with double tilde
let g:vim_markdown_math = 1  " Enable Latex syntax highlight

let g:vim_markdown_new_list_item_indent = 2  " When inserting a new list item, indent it by two spaces
let g:vim_markdown_auto_insert_bullets = 1  " Automatically insert bullets in Markdown

let g:vim_markdown_follow_anchor = 1  " Open anchored links with `ge`
let g:vim_markdown_no_extensions_in_markdown = 1  " Open links (without extensions) with `ge`

let g:vim_markdown_folding_disabled = 1  " Disable folding
let g:vim_markdown_conceal = 0  " Disable syntax concealing.
let g:vim_markdown_conceal_code_blocks = 0  " Disable code blocks concealing.
" }}}

function! HeaderDecrease() abort
    if match(getline('.'), '^# ') > -1
        let l:search = @/
        execute 'silent! substitute/^# //'
        let @/=l:search
        return
    endif

    execute '.HeaderDecrease'
endfunction

function! HeaderIncrease() abort
    if match(getline('.'), '^#') > -1
        execute '.HeaderIncrease'
        return
    endif

    let l:search = @/
    execute 'silent! substitute/^/# /'
    let @/=l:search
endfunction

function! FenceStart() abort
    call search('```.\+$', 'bW')
endfunction

function! FenceEnd() abort
    call search('```$', 'W')
endfunction
