" if !exists('*lightline.init')
"     finish
" end

let g:lightline = {}

let g:lightline.component_expand = {
            \ 'tabs': 'lightline#tabs',
            \ 'syntax_error': 'aldur#lightline#ale_error',
            \ 'syntax_warning': 'aldur#lightline#ale_warning',
            \ 'syntax_info': 'aldur#lightline#ale_info',
            \ }

let g:lightline.component_type = {
            \ 'tabs': 'tabsel',
            \ 'close': 'raw',
            \ 'syntax_error': 'error',
            \ 'syntax_warning': 'warning',
            \ 'syntax_info': 'info',
            \ }

" Setup the active status bar
let g:lightline.active = {
            \ 'left': [ [ 'mode', 'paste', 'spell' ],
            \           [ 'readonly', 'filename', 'modified' ] ],
            \ 'right': [ [ 'syntax_error', 'syntax_warning', 'syntax_info' ],
            \            [ 'lineinfo' ],
            \            [ 'fileformat', 'fileencoding', 'filetype' ],
            \            [ 'virtualenv' ] ] }

" Setup the inactive status bar
let g:lightline.inactive = {
            \ 'left': [ [ 'filename' ] ],
            \ 'right': [ [ 'percent' ] ] }


" Setup tab components
let g:lightline.tab_component_function = {
        \ 'filename': 'lightline#tab#filename',
        \ 'modified': 'lightline#tab#modified',
        \ 'tabnum': 'lightline#tab#tabnum' }

" Setup the tab bar
let g:lightline.tabline = {
        \ 'left': [ [ 'tabs' ] ],
        \ 'right': [ ] }

let g:lightline.tab = {
    \ 'active': [ 'filename', 'modified' ],
    \ 'inactive': [ 'tabnum', 'filename', 'modified' ] }

