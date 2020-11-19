function! aldur#find_root#find_root() abort
    let l:base = '%:p:h'
    if exists('b:netrw_curdir')
        let l:base = b:netrw_curdir
    endif

    try
        " If possible, execut FZF from the current project root.
        " We're using gutentags#get_project_root for the task.
        let l:root = gutentags#get_project_root(expand(l:base, 1))
    catch
        let l:root = expand(l:base, 1)
    endtry

    " If it's a terminal, then we default to cwd
    if l:root =~# 'term://'
        let l:root = getcwd()
    endif

    return l:root
endfunction

