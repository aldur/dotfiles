" undofile - This allows you to use undos after exiting and restarting
" This, like swap and backups, uses .vim-undo first, then ~/.vim_backups/undo
" :help undo-persistence
" This is only present in 7.3+
if isdirectory($HOME . '/.vim_backups/undo') == 0
    call mkdir($HOME . '/.vim_backups/undo', 'p')
endif
set undodir=./.vim-undo//
set undodir+=~/.vim_backups/undo//
set undofile
