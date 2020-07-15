scriptencoding utf-8

" ALE integration {{{
    function! aldur#lightline#ale_error() abort
        let l:counts = ale#statusline#Count(bufnr(''))
        let l:errors = l:counts.error + l:counts.style_error
        return l:errors > 0 ? '☢ '.l:errors : ''
    endfunction

    function! aldur#lightline#ale_warning() abort
        let l:counts = ale#statusline#Count(bufnr(''))
        let l:warnings = l:counts.warning + l:counts.style_warning
        return l:warnings > 0 ? '⚠ '.l:warnings : ''
    endfunction

    function! aldur#lightline#ale_info() abort
        let l:counts = ale#statusline#Count(bufnr(''))
        let l:infos = l:counts.info
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
