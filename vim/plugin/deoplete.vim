let g:deoplete#enable_at_startup = 1  " Enable deoplete
if !(&runtimepath =~# 'deoplete')
    finish
endif

call deoplete#custom#option({
            \ 'smart_case': v:true,
            \ 'max_list': 20,
            \ })

call deoplete#custom#source('ultisnips', 'rank', 1000) " Keep snippets on top

let s:default_sources = ['buffer', 'member', 'tag', 'file', 'ultisnips']  " 'omni' is disabled 'cause is not async
" cpp completion provided by CCLS
" py completion provided by python-language-server
" latex completion provided by texlab
call deoplete#custom#option('sources', {
            \ '_': s:default_sources,
            \ 'cpp': s:default_sources + ['ale'],
            \ 'vim': s:default_sources + ['vim'],
            \ 'tex': s:default_sources + ['look'] + ['ale'],
            \ 'gitcommit': s:default_sources + ['look'],
            \ 'markdown': s:default_sources + ['look'],
            \ 'vimwiki': s:default_sources + ['look'] + ['omni'],
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
