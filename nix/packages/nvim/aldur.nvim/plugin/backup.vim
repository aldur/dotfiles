" Save your backups to a less annoying place than the current directory.
if isdirectory($HOME . '/.vim_backups/backup') == 0
    call mkdir($HOME . '/.vim_backups/backup', 'p')
endif
" Override the defaults.
set backupdir=~/.vim_backups/backup/
set backup

set noswapfile  " Stop annoying swap files
