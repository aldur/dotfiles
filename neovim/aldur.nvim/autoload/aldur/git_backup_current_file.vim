let s:custom_backup_dir = $HOME . '/.vim_backups/git_backups/'
let s:author = '-c user.name="nvim backup" -c user.email="nvim_backup@localhost"'

function! s:Init() abort
    if isdirectory(s:custom_backup_dir) == 0 && executable('git')
        call mkdir(s:custom_backup_dir, 'p')
        call system('git init ' . s:custom_backup_dir)
        if v:shell_error
            echoerr 'could not init git directory'
            call s:Disarm()
            return
        endif
        call system('chmod 700 ' . s:custom_backup_dir)
        if v:shell_error
            echoerr 'could not chmod git directory'
            call s:Disarm()
            return
        endif
        call system('git ' . s:author . ' -C ' . s:custom_backup_dir . ' commit --allow-empty -m "Initial commit"')
        if v:shell_error
            echoerr 'could not create initial commit'
            call s:Disarm()
            return
        endif
    endif
endfunction

call s:Init()

function! s:Disarm() abort
    echomsg "Error detected, disarming automatic git backups..."
    autocmd! GitBackupCurrentFile
endfunction

let s:buffer = ""

function! s:Receive(_job_id, data, event) abort
    let s:buffer .= a:event . " " . string(a:data)
    let s:buffer .= "\n"
    if a:event ==# 'exit'
        if a:data != 0
            echoerr printf('Unexpected exit code: %s', string(a:data))
            echoerr s:buffer
            call s:Disarm()
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

    let l:cmd = ''
    let l:cmd .= 'cp "' . l:file . '" "' . l:backup_file . '"; '
    let l:cmd .= 'cd "' . l:backup_dir . '"; '
    let l:cmd .= 'git add "' . l:backup_file . '"; '
    let l:cmd .= 'git diff-index --quiet HEAD -- || git ' . s:author . ' commit --no-gpg-sign -m "Backup ' . l:file . '"; '

    let s:buffer = ""
    let l:callbacks = {
                \ 'on_stdout': function('s:Receive'),
                \ 'on_stderr': function('s:Receive'),
                \ 'on_exit': function('s:Receive')
                \ }

    let l:result = jobstart(['bash', '-c', l:cmd], l:callbacks)
    if l:result <= 0
        echoerr "Invalid l:result returned by jobstart for `git_backup_current_file`."
        call s:Disarm()
    endif
endfunction
