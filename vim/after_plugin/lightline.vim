if !exists('*lightline.init')
    finish
end

let g:lightline = {}

" Setup the single components
let g:lightline.component = {
            \ 'mode': '%{lightline#mode()}',
            \ 'absolutepath': '%F',
            \ 'relativepath': '%f',
            \ 'filename': '%t',
            \ 'modified': '%M',
            \ 'bufnum': '%n',
            \ 'paste': '%{&paste?"P":""}',
            \ 'readonly': '%R',
            \ 'charvalue': '%b',
            \ 'charvaluehex': '%B',
            \ 'fileencoding': '%{&fenc!=#""?&fenc:&enc}',
            \ 'fileformat': '%{&ff}',
            \ 'filetype': '%{&ft!=#""?&ft:"no ft"}',
            \ 'percent': '%3p%%',
            \ 'percentwin': '%P',
            \ 'spell': '%{&spell?&spelllang:""}',
            \ 'separator': '',
            \ 'lineinfo': '%3l:%-2v',
            \ 'line': '%l',
            \ 'column': '%c',
            \ 'close': '%999X X ' }

let g:lightline.component_function = {
            \ 'mode': 'LightlineMode',
            \ 'bufferinfo': 'lightline#buffer#bufferinfo',
            \ }

let g:lightline.component_expand = {
            \ 'tabs': 'lightline#tabs',
            \ 'buffercurrent': 'lightline#buffer#buffercurrent',
            \ 'bufferbefore': 'lightline#buffer#bufferbefore',
            \ 'bufferafter': 'lightline#buffer#bufferafter',
            \ 'virtualenv': 'LightlineVirtualenv',
            \ 'syntax_error': 'LightlineNeomakeError',
            \ 'syntax_warning': 'LightlineNeomakeWarning',
            \ 'syntax_info': 'LightlineNeomakeInfo',
            \ }

let g:lightline.component_type = {
            \ 'syntax_error': 'error',
            \ 'syntax_warning': 'warning',
            \ 'syntax_info': 'info',
            \ 'buffercurrent': 'tabsel',
            \ 'bufferbefore': 'raw',
            \ 'bufferafter': 'raw',
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
            \ 'right': [ [ 'lineinfo' ],
            \            [ 'percent' ] ] }

function! LightlineMode() abort
    return winwidth(0) > 60 ? lightline#mode() : ''
endfunction

" Virtualenv integration
function! LightlineVirtualenv() abort
    return &filetype ==? 'python' ? virtualenv#statusline() : ''
endfunction

" Neomake integration {{{
    function! LightlineNeomakeError() abort
        let l:errors = get(neomake#statusline#LoclistCounts(), 'E', 0)
        return l:errors > 0 ? 'E: '.l:errors : ''

        let l:warning = get(neomake#statusline#LoclistCounts(), 'E', 0)
        let l:infos = get(neomake#statusline#LoclistCounts(), 'E', 0)
    endfunction

    function! LightlineNeomakeWarning() abort
        let l:warnings = get(neomake#statusline#LoclistCounts(), 'W', 0)
        return l:warnings > 0 ? 'W: '.l:warnings : ''
    endfunction

    function! LightlineNeomakeInfo() abort
        let l:infos = get(neomake#statusline#LoclistCounts(), 'I', 0)
        return l:infos > 0 ? 'I: '.l:infos : ''
    endfunction
" }}}
