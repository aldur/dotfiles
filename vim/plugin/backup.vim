" Save your backups to a less annoying place than the current directory.
" If you have .vim-backup in the current directory, it'll use that.
" Otherwise it saves it to ~/.vim_backups/backup or . if all else fails.
if isdirectory($HOME . '/.vim_backups/backup') == 0
    call mkdir($HOME . '/.vim_backups/backup', 'p')
endif
set backupdir-=.
set backupdir-=~/
set backupdir-=~/.local/share/nvim/backup
set backupdir^=~/.vim_backups/backup/
set backup

set noswapfile  " Stop annoying swap files

