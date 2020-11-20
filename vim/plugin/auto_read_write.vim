" Set to auto read when a file is changed from an outside command
set autoread

" And trigger it when files changes on disk outside of VIM
" We ignore `nofile` buffers to make sure that this works in the command-line window
autocmd vimrc FocusGained,BufEnter,CursorHold,CursorHoldI * if (mode() != 'c' && &buftype != 'nofile') | checktime | endif
autocmd vimrc FileChangedShellPost *
            \ echohl WarningMsg | echo "File changed on disk. Buffer reloaded." | echohl None

" Auto save on :next, :edit, :quit, etc.
set autowriteall  " Implies `autowrite`

" When transparently editing remote buffers through Netrw, we disable `autowriteall`
autocmd vimrc BufEnter * if exists('b:netrw_lastfile') | setlocal noautowriteall | endif

" ... when changing window
autocmd vimrc WinLeave * :call aldur#auto_read_write#write_gently()

" ... and on focus lost
autocmd vimrc FocusLost * :silent! wall
