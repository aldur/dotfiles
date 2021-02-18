let g:deoplete#enable_at_startup = 1  " Enable deoplete
if !(&runtimepath =~# 'deoplete')
    finish
endif

call deoplete#custom#option({
            \ 'smart_case': v:true,
            \ 'max_list': 20,
            \ })

call deoplete#custom#source('ultisnips', 'rank', 1000) " Keep snippets on top

" The `dictionary` source requires `set complete+=k` and at least one dictionary file set.

" Remove this if you'd like to use fuzzy search
" XXX 2020-11-13: I removed this to enable fuzzy search on the dictionary.
" call deoplete#custom#source(
"             \ 'dictionary', 'matchers', ['matcher_head'])

" If dictionary is already sorted, no need to sort it again.
call deoplete#custom#source(
            \ 'dictionary', 'sorters', [])
" Do not complete too short words
call deoplete#custom#source(
            \ 'dictionary', 'min_pattern_length', 5)

" Set `fuzzy` finding for files.
call deoplete#custom#source(
            \ 'file', 'matchers', ['matcher_fuzzy'])

" 'omni' is disabled 'cause is not async
let s:default_sources = ['around', 'member', 'tag', 'file', 'ultisnips']

" cpp completion provided by CCLS
" py completion provided by python-language-server
" latex completion provided by texlab
" go completion provided by gopls
call deoplete#custom#option('sources', {
            \ '_': s:default_sources,
            \ 'cpp': s:default_sources + ['ale'],
            \ 'vim': s:default_sources + ['vim'],
            \ 'tex': s:default_sources + ['dictionary'] + ['ale'],
            \ 'gitcommit': s:default_sources + ['dictionary'],
            \ 'markdown': s:default_sources + ['notes', 'notes_tags'] + ['dictionary'],
            \ 'markdown.wiki': s:default_sources + ['notes', 'notes_tags'] + ['dictionary'],
            \ 'python': s:default_sources + ['ale'],
            \ 'go': s:default_sources + ['ale'],
            \ 'rust': s:default_sources + ['ale'],
            \})

" Clever tab to cycle the completion popup menu
" If you even need to insert a literal tab, press <CTRL-V><Tab>
inoremap <silent><expr> <TAB> aldur#deoplete#tab_imap()

" Add a command to quickly toggle deoplete.
command! DeopleteToggle call deoplete#toggle()
