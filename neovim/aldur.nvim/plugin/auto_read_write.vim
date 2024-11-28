" Set to auto read when a file is changed from an outside command
set autoread

" And trigger it when files changes on disk outside of VIM
" We ignore `nofile` buffers to make sure that this works in the command-line window
autocmd vimrc FocusGained,BufEnter,TabEnter,CursorHold,CursorHoldI * if (mode() != 'c' && &buftype != 'nofile') | checktime | endif
autocmd vimrc FileChangedShellPost *
            \ echohl WarningMsg | echo "File changed on disk. Buffer reloaded." | echohl None

" Auto save on :next, :edit, :quit, etc.
set autowriteall  " Implies `autowrite`

" Add buffer to v:oldfiles
autocmd vimrc BufNew * :call aldur#auto_read_write#add_to_oldfiles()

" ... when changing window
autocmd vimrc WinLeave * :call aldur#auto_read_write#write_gently()

" ... and on focus lost
autocmd vimrc FocusLost * :silent! wall
