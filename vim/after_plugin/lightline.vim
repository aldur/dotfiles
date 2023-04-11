if !exists('g:loaded_lightline')
    finish
end

let g:lightline = {}

" === Setup the lightline colorscheme ===
if g:colors_name == 'sonokai'
    let g:lightline.colorscheme = 'sonokai'
end
" === /Setup the lightline colorscheme ===

let g:lightline.component_expand = {
            \ 'tabs': 'lightline#tabs',
            \ 'syntax_error': 'aldur#lightline#lsp_error',
            \ 'syntax_warning': 'aldur#lightline#lsp_warning',
            \ 'syntax_info': 'aldur#lightline#lsp_info',
            \ }

let g:lightline.component_function = {
            \ 'gitbranch': 'aldur#lightline#git_branch',
            \ 'readonly': 'aldur#lightline#read_only',
            \ 'filename': 'aldur#lightline#filename',
            \ 'filetype': 'aldur#lightline#filetype',
            \ 'spell': 'aldur#lightline#spell',
            \ }

" Custom component for file encoding and format
let g:lightline.component = {
    \ 'fileencoding': '%{&fenc!=#"utf-8"?(&fenc!=#""?&fenc:&enc):""}',
    \ 'fileformat': '%{&ff!=#"unix"?&ff:""}',
    \ }

" ...and companions to define visibility
let g:lightline.component_visible_condition = {
    \ 'fileencoding': '&fenc!=#"utf-8"',
    \ 'fileformat': '&ff!=#"unix"',
    \ 'treesitter': 'aldur#lightline#treesitter()!=""'
    \ }

let g:lightline.component_type = {
            \ 'tabs': 'tabsel',
            \ 'syntax_error': 'error',
            \ 'syntax_warning': 'warning',
            \ 'syntax_info': 'info',
            \ }

" Setup the active status bar
let g:lightline.active = {
            \ 'left' : [ [ 'mode', 'paste', 'spell'                        ],
            \            [ 'readonly', 'filename'                          ],
            \            [ 'gitbranch'                                     ] ],
            \ 'right': [ [ 'syntax_error', 'syntax_warning', 'syntax_info' ],
            \            [ 'lineinfo'                                      ],
            \            [ 'fileformat', 'fileencoding', 'filetype'        ],
            \            [ 'treesitter'                                    ],
            \            [ 'virtualenv'                                    ] ] }

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

let g:lightline.mode_map = {
            \ 'n' : 'NRM',
            \ 'i' : 'INS',
            \ 'R' : 'RPL',
            \ 'v' : 'VSL',
            \ 'V' : 'VLN',
            \ "\<C-v>": 'VBL',
            \ 'c' : 'CMD',
            \ 's' : 'SEL',
            \ 'S' : 'SLN',
            \ "\<C-s>": 'SBL',
            \ 't': 'TRM',
            \ }
