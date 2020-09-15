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

" The following lines should fix a bug in neovim in which undoing causes the
" cursor to jump around.
" https://stackoverflow.com/questions/31548025/vim-undo-why-does-the-cursor-jump-to-the-wrong-position-when-undoing-undojoin
" --- UNDO NVIM FIX ---
function! s:safeundo()
    call aldur#stay#stay('undo')
endfunc

function! s:saferedo()
    call aldur#stay#stay('redo')
endfunc

nnoremap u :call <sid>safeundo()<CR>
nnoremap <C-r> :call <sid>saferedo()<CR>
" --- /UNDO NVIM FIX ---
