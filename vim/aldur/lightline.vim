scriptencoding utf-8

" LSP integration {{{
    function! aldur#lightline#lsp_error() abort
        let l:errors = 0
        if luaeval('not vim.tbl_isempty(vim.lsp.buf_get_clients(0))')
            let l:errors = luaeval('vim.lsp.diagnostic.get_count(0, [[Error]])')
        endif
        return l:errors > 0 ? '☢ '.l:errors : ''
    endfunction

    function! aldur#lightline#lsp_warning() abort
        let l:warnings = 0
        if luaeval('not vim.tbl_isempty(vim.lsp.buf_get_clients(0))')
            let l:warnings = luaeval('vim.lsp.diagnostic.get_count(0, [[Warning]])')
        endif
        return l:warnings > 0 ? '⚠ '.l:warnings : ''
    endfunction

    function! aldur#lightline#lsp_info() abort
        let l:infos = 0
        if luaeval('not vim.tbl_isempty(vim.lsp.buf_get_clients(0))')
            let l:infos = luaeval('vim.lsp.diagnostic.get_count(0, [[Information]])')
        endif
        return l:infos > 0 ? 'ℹ '.l:infos : ''
    endfunction
" }}}


function! aldur#lightline#read_only()
    return &readonly ? '' : ''
endfunction

function! aldur#lightline#git_branch()
    let branch = FugitiveStatusline()
    if !empty(branch)
        let branch = substitute(branch, '[Git', '', '')
        let branch = substitute(branch, ']', '', '')

        if stridx(branch, ":") != -1
            let branch = substitute(branch, ':', '', '')
            let branch = substitute(branch, '\v\(.*', '', '')
        else
            let branch = substitute(branch, '(', '', '')
            let branch = substitute(branch, ')', '', '')
        endif

        return branch !=# '' ? ' '.branch : ''
    endif
    return ''
endfunction

function! aldur#lightline#filename()
    " Merge the filename and the modified tag
    let filename = expand('%:t') !=# '' ? expand('%:t') : '[No Name]'
    let modified = &modified ? ' +' : ''
    return filename . modified
endfunction

function! aldur#lightline#filetype()
    return winwidth(0) > 70 ? (&filetype !=# '' ? &filetype : 'no ft') : ''
endfunction

function! aldur#lightline#spell()
    return winwidth(0) > 70 ? (&spell?&spelllang:'') : ''
endfunction

lua << EOF
function _G.lightline_tresitter()
    if vim.fn.winwidth(0) > 70 then
        local ts = require'nvim-treesitter'.statusline({
            indicator_size=50,
            transform_fn=function(line)
                local filetypes = vim.split(vim.bo.filetype, '.', true)
                if vim.tbl_contains(filetypes, 'python') then
                    line = line:gsub('class ', '')
                    line = line:gsub('def ', '')
                    line = line:gsub('%s*->%s*.+%s*:', '')
                    line = line:gsub('%(.*%)', '')
                    line = line:gsub(':', '')
                end
                return line:gsub('%s*[%[%(%{]*%s*$', '')
            end,
        })
        if ts ~= nil then
            return ts
        end
    end

    return ''
end
EOF

function! aldur#lightline#treesitter()
    return v:lua.lightline_tresitter()
endfunction
