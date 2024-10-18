if !executable('git')
    finish
endif

augroup GitBackupCurrentFile
    autocmd!
    autocmd BufWritePost * call aldur#git_backup_current_file#backup()
augroup end
