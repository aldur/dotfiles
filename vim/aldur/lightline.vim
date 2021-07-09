scriptencoding utf-8

" ALE integration {{{
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
    if exists('*FugitiveHead')
        let l:branch = FugitiveHead()
        return l:branch !=# '' ? ' '.branch : ''
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

function! aldur#lightline#treesitter()
    if winwidth(0) > 70
        let l:s = nvim_treesitter#statusline()
        if l:s != v:null
            return l:s
        endif
    endif

    return ''
endfunction
