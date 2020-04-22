" if !exists('*lightline.init')
"     finish
" end

let g:lightline = {}

let g:lightline.component_expand = {
            \ 'tabs': 'lightline#tabs',
            \ 'virtualenv': 'LightlineVirtualenv',
            \ 'syntax_error': 'LightlineAleError',
            \ 'syntax_warning': 'LightlineAleWarning',
            \ 'syntax_info': 'LightlineAleInfo',
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

" Virtualenv integration
function! LightlineVirtualenv() abort
    return &filetype ==? 'python' ? virtualenv#statusline() : ''
endfunction

" Neomake integration {{{
    function! LightlineAleError() abort
        let l:counts = ale#statusline#Count(bufnr(''))
        let l:errors = l:counts.error + l:counts.style_error
        return l:errors > 0 ? 'E: '.l:errors : ''
    endfunction

    function! LightlineAleWarning() abort
        let l:counts = ale#statusline#Count(bufnr(''))
        let l:warnings = l:counts.warning + l:counts.style_warning
        return l:warnings > 0 ? 'W: '.l:warnings : ''
    endfunction

    function! LightlineAleInfo() abort
        let l:counts = ale#statusline#Count(bufnr(''))
        let l:infos = l:counts.info
        return l:infos > 0 ? 'I: '.l:infos : ''
    endfunction
" }}}
