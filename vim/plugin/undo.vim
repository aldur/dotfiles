" undofile - This allows you to use undos after exiting and restarting
" This, like swap and backups, uses .vim-undo first, then ~/.vim/undo
" :help undo-persistence
" This is only present in 7.3+
if isdirectory($HOME . '/.vim/undo') == 0
    call mkdir($HOME . '/.vim/undo', 'p')
endif
set undodir=./.vim-undo//
set undodir+=~/.vim/undo//
set undofile
