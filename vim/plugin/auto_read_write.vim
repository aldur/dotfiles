" Set to auto read when a file is changed from an outside command
set autoread

" And trigger it when files changes on disk outside of VIM
autocmd vimrc FocusGained,BufEnter,CursorHold,CursorHoldI * if mode() != 'c' | checktime | endif
autocmd vimrc FileChangedShellPost *
            \ echohl WarningMsg | echo "File changed on disk. Buffer reloaded." | echohl None

" Auto save on :next, :edit, :quit, etc.
set autowrite
set autowriteall

" ... and on focus lost
autocmd vimrc FocusLost * :silent! wall
