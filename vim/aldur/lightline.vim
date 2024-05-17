scriptencoding utf-8

" LSP integration {{{
    function! aldur#lightline#lsp_error() abort
        let l:errors = 0
        if luaeval('not vim.tbl_isempty(vim.lsp.buf_get_clients(0))')
            let l:errors = luaeval('#vim.diagnostic.get(0, {severity=vim.diagnostic.severity.ERROR})')
        endif
        return l:errors > 0 ? '☢ '.l:errors : ''
    endfunction

    function! aldur#lightline#lsp_warning() abort
        let l:warnings = 0
        if luaeval('not vim.tbl_isempty(vim.lsp.buf_get_clients(0))')
            let l:warnings = luaeval('#vim.diagnostic.get(0, {severity=vim.diagnostic.severity.WARN})')
        endif
        return l:warnings > 0 ? '⚠ '.l:warnings : ''
    endfunction

    function! aldur#lightline#lsp_info() abort
        let l:infos = 0
        if luaeval('not vim.tbl_isempty(vim.lsp.buf_get_clients(0))')
            let l:infos = luaeval('#vim.diagnostic.get(0, {severity={max = vim.diagnostic.severity.INFO}})')
        endif
        return l:infos > 0 ? 'ℹ '.l:infos : ''
    endfunction
" }}}


function! aldur#lightline#read_only()
    return &readonly ? '' : ''
endfunction

function! aldur#lightline#pwd_is_root()
    return aldur#find_root#pwd_is_root() ? '🌳' : ''
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
