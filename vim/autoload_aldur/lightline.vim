" ALE integration {{{
    function! aldur#lightline#ale_error() abort
        let l:counts = ale#statusline#Count(bufnr(''))
        let l:errors = l:counts.error + l:counts.style_error
        return l:errors > 0 ? 'E: '.l:errors : ''
    endfunction

    function! aldur#lightline#ale_warning() abort
        let l:counts = ale#statusline#Count(bufnr(''))
        let l:warnings = l:counts.warning + l:counts.style_warning
        return l:warnings > 0 ? 'W: '.l:warnings : ''
    endfunction

    function! aldur#lightline#ale_info() abort
        let l:counts = ale#statusline#Count(bufnr(''))
        let l:infos = l:counts.info
        return l:infos > 0 ? 'I: '.l:infos : ''
    endfunction
" }}}
