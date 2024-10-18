if !executable('git')
    finish
endif

augroup GitBackupCurrentFile
    autocmd!
augroup end
autocmd GitBackupCurrentFile BufWritePost * call aldur#git_backup_current_file#backup()
