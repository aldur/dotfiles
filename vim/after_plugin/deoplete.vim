if !exists('*deoplete#manual_complete')
    finish
endif

let g:deoplete#enable_smart_case = 1 " Enable smartcase

let g:deoplete#sources           = {}
let g:deoplete#sources._         = ['buffer', 'member', 'tag', 'file', 'ultisnips']  " Disabled 'omni' 'cause it's not async
let g:deoplete#sources.vim       = g:deoplete#sources._ + ['vim']
let g:deoplete#sources.tex       = g:deoplete#sources._ + ['look', 'omni']
let g:deoplete#sources.gitcommit = g:deoplete#sources._ + ['look']
let g:deoplete#sources.python    = g:deoplete#sources._ + ['jedi']
let g:deoplete#sources.go        = g:deoplete#sources._ + ['go']

let g:deoplete#max_list       = 20 " Show 20 entries at most
let g:deoplete#max_menu_width = 20 " Matches the list length

let g:deoplete#skip_chars = ['(', ')']

if &runtimepath =~# 'deoplete'
    call deoplete#custom#source('ultisnips', 'rank', 1000) " Keep snippets on top
endif

" Go completion settings
let g:deoplete#sources#go#gocode_binary = $GOPATH . '/bin/gocode'
let g:deoplete#sources#go#sort_class    = ['package', 'func', 'type', 'var', 'const']
let g:deoplete#sources#go#use_cache     = 0

" vim-tex integration
if !exists('g:deoplete#omni#input_patterns')
    let g:deoplete#omni#input_patterns = {}
endif

let g:deoplete#omni#input_patterns.tex = '\\(?:'
            \ .  '\w*cite\w*(?:\s*\[[^]]*\]){0,2}\s*{[^}]*'
            \ . '|\w*ref(?:\s*\{[^}]*|range\s*\{[^,}]*(?:}{)?)'
            \ . '|hyperref\s*\[[^]]*'
            \ . '|includegraphics\*?(?:\s*\[[^]]*\]){0,2}\s*\{[^}]*'
            \ . '|(?:include(?:only)?|input)\s*\{[^}]*'
            \ . '|\w*(gls|Gls|GLS)(pl)?\w*(\s*\[[^]]*\]){0,2}\s*\{[^}]*'
            \ . '|includepdf(\s*\[[^]]*\])?\s*\{[^}]*'
            \ . '|includestandalone(\s*\[[^]]*\])?\s*\{[^}]*'
            \ .')'

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
