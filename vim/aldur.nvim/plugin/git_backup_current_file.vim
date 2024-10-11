if !executable('git')
    finish
endif

autocmd vimrc BufWritePost * call aldur#git_backup_current_file#backup()
