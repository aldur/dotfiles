if !exists('g:loaded_lightline')
    finish
end

let g:lightline = {}

let g:lightline.tabnames = {}

lua <<EOF
vim.api.nvim_create_user_command('SetTabName', function(opts)
    local name = opts.fargs[1]
    local tab_index = vim.fn['tabpagenr']()

    -- Setting dictionary fields in Lua does not write them back to nvim.
    -- See :h lua-vim-variables
    local lightline = vim.g.lightline
    lightline.tabnames[tostring(tab_index)] = name
    vim.g.lightline = lightline

    vim.fn['lightline#highlight']()
end, {desc="Assign a name to a tab.", force=true, nargs=1})
EOF

" === Setup the lightline colorscheme ===
if g:colors_name ==# 'sonokai'
    let g:lightline.colorscheme = 'sonokai'
end
" === /Setup the lightline colorscheme ===

let g:lightline.component_expand = {
            \ 'tabs': 'lightline#tabs',
            \ 'syntax_error': 'aldur#lightline#lsp_error',
            \ 'syntax_warning': 'aldur#lightline#lsp_warning',
            \ 'syntax_info': 'aldur#lightline#lsp_info',
            \ 'llm_processing': 'aldur#lightline#llm_processing',
            \ }

let g:lightline.component_function = {
            \ 'gitbranch': 'aldur#lightline#git_branch',
            \ 'readonly': 'aldur#lightline#read_only',
            \ 'pwd_is_root': 'aldur#lightline#pwd_is_root',
            \ 'pwd': 'aldur#lightline#pwd',
            \ 'direnv_shell_enabled': 'aldur#lightline#direnv_shell_enabled',
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
    \ }

let g:lightline.component_type = {
            \ 'tabs': 'tabsel',
            \ 'syntax_error': 'error',
            \ 'syntax_warning': 'warning',
            \ 'syntax_info': 'info',
            \ 'llm_processing': 'info',
            \ }

" Setup the active status bar
let g:lightline.active = {
            \ 'left' : [ [ 'mode', 'paste', 'spell'                                          ],
            \            [ 'readonly', 'pwd_is_root', 'direnv_shell_enabled','filename'      ],
            \            [ 'gitbranch', 'pwd'                                                ] ],
            \ 'right': [ [ 'llm_processing', 'syntax_error', 'syntax_warning', 'syntax_info' ],
            \            [ 'lineinfo'                                                        ],
            \            [ 'fileformat', 'fileencoding', 'filetype'                          ] ] }

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
    \ 'active': [ 'tabname_or_filename'],
    \ 'inactive': [ 'tabnum', 'tabname_or_filename'] }

let g:lightline.tab_component_function = {
		      \ 'tabname_or_filename': 'aldur#lightline#tabname_or_filename'
              \    }

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
