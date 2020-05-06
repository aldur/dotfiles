let g:deoplete#enable_at_startup = 1  " Enable deoplete
if !(&runtimepath =~# 'deoplete')
    finish
endif

call deoplete#custom#option({
            \ 'smart_case': v:true,
            \ 'max_list': 20,
            \ })

call deoplete#custom#source('ultisnips', 'rank', 1000) " Keep snippets on top

" This requires `set complete+=k` and a dictionary file set.
" Sample configuration for dictionary source with multiple dictionary files.
" Remove this if you'd like to use fuzzy search
call deoplete#custom#source(
            \ 'dictionary', 'matchers', ['matcher_head'])
" If dictionary is already sorted, no need to sort it again.
call deoplete#custom#source(
            \ 'dictionary', 'sorters', [])
" Do not complete too short words
call deoplete#custom#source(
            \ 'dictionary', 'min_pattern_length', 2)

let s:default_sources = ['around', 'member', 'tag', 'file', 'ultisnips']  " 'omni' is disabled 'cause is not async
" cpp completion provided by CCLS
" py completion provided by python-language-server
" latex completion provided by texlab
call deoplete#custom#option('sources', {
            \ '_': s:default_sources,
            \ 'cpp': s:default_sources + ['ale'],
            \ 'vim': s:default_sources + ['vim'],
            \ 'tex': s:default_sources + ['dictionary'] + ['ale'],
            \ 'gitcommit': s:default_sources + ['look'],
            \ 'markdown': s:default_sources + ['notes', 'notes_tags'] + ['dictionary'],
            \ 'python': s:default_sources + ['ale'],
            \ 'go': s:default_sources + ['go'],
            \})

" Go completion settings
let g:deoplete#sources#go#gocode_binary = $GOPATH . '/bin/gocode'
let g:deoplete#sources#go#sort_class    = ['package', 'func', 'type', 'var', 'const']

" vim-tex integration
" if exists('g:vimtex#re#deoplete')
"     call deoplete#custom#var('omni', 'input_patterns', {
"                 \ 'tex': g:vimtex#re#deoplete
"                 \})
" endif

function! s:check_back_space() abort
    let l:col = col('.') - 1
    return !l:col || getline('.')[l:col - 1]  =~? '\s'
endfunction

" Clever tab to cycle the completion popup menu
" If you even need to insert a literal tab, press <CTRL-V><Tab>
inoremap <silent><expr> <TAB>
            \ pumvisible() ? "\<C-n>" :
            \ <SID>check_back_space() ? "\<TAB>" :
            \ deoplete#manual_complete()

" Add a command to quickly toggle deoplete.
command! DeopleteToggle call deoplete#toggle()
