let s:custom_backup_dir = $HOME . '/.vim_backups/git_backups/'
if isdirectory(s:custom_backup_dir) == 0 && executable('git')
    call mkdir(s:custom_backup_dir, 'p')
    call system('git init ' . s:custom_backup_dir)
    call system('chmod 700 ' . s:custom_backup_dir)
endif

" Backup file modifications through GIT.
function! aldur#git_backup_current_file#backup() abort
    if &buftype  " if it is set, return
        return
    endif

    " If we are root, we write to the `as_root` directory
    " to avoid permissions on later writes.
    let l:backup_dir = s:custom_backup_dir
    if $USER =~ 'root'
        let l:backup_dir .= 'as_root'
    endif

    let l:file = expand('%:p')
    if l:backup_dir =~ l:file
        return
    endif

    let l:file_dir = l:backup_dir . expand('%:p:h')
    let l:backup_file = l:backup_dir . l:file

    if !isdirectory(expand(l:file_dir))
        call mkdir(l:file_dir, 'p')
    endif

    let l:cmd = 'cp "' . l:file . '" "' . l:backup_file . '";'
    let l:cmd .= 'cd "' . l:backup_dir . '";'
    let l:cmd .= 'git add "' . l:backup_file . '";'
    let l:cmd .= 'git commit -m "Backup ' . l:file . '";'
    if has('nvim')
        call jobstart(l:cmd)
    else
        call job_start(l:cmd)
    endif
endfunction
