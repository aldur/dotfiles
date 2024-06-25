let s:custom_backup_dir = $HOME . '/.vim_backups/git_backups/'
if isdirectory(s:custom_backup_dir) == 0 && executable('git')
    call mkdir(s:custom_backup_dir, 'p')
    call system('git init ' . s:custom_backup_dir)
    call system('chmod 700 ' . s:custom_backup_dir)
endif

let s:buffer = ""

function! s:Receive(_job_id, data, event) abort
    let s:buffer .= a:event . " " . string(a:data)
    let s:buffer .= "\n"
    if a:event ==# 'exit'
        if a:data != 0
            echoerr printf('Unexpected exit code: %s', string(a:data))
            echoerr s:buffer
        endif
    endif
endfunction

" Backup file modifications through GIT.
function! aldur#git_backup_current_file#backup() abort
    if &buftype  " if it is set, return
        return
    endif

    " If we are using sudo, we write to the `as_sudo` directory
    " to avoid permissions on later writes.
    let l:backup_dir = s:custom_backup_dir
    if !empty($SUDO_USER)
        let l:backup_dir .= 'as_sudo'
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

    let l:cmd = 'cp "' . l:file . '" "' . l:backup_file . '"; '
    let l:cmd .= 'cd "' . l:backup_dir . '"; '
    let l:cmd .= 'git add "' . l:backup_file . '"; '
    let l:cmd .= 'git diff-index --quiet HEAD || git commit --no-gpg-sign -m "Backup ' . l:file . '"; '

    if has('nvim')
        let s:buffer = ""
        let l:callbacks = {
                    \ 'on_stdout': function('s:Receive'),
                    \ 'on_stderr': function('s:Receive'),
                    \ 'on_exit': function('s:Receive')
                    \ }

        let l:result = jobstart(['bash', '-c', l:cmd], l:callbacks)
        if l:result <= 0
            echoerr "Invalid l:result returned by jobstart for `git_backup_current_file`."
        endif
    else
        call job_start(l:cmd)
    endif
endfunction
