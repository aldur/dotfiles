if isdirectory($HOME . '/.vim_backups') == 0
    call mkdir($HOME . '/.vim_backups', 'p')
endif

" Tell (n)vim to remember certain things when we exit
"  '100  :  marks will be remembered for up to 100 previously edited files
"  "100 :  will save up to 100 lines for each register
"  <100 :  will save up to 100 lines for each register (new alternative to ")
"  %    :  saves and restores the buffer list
"  n... :  where to save the viminfo files
if has('nvim')
    set shada='100,<100,%,n~/.vim_backups/nviminfo
else
    set viminfo='100,\"100,%,n~/.vim_backups/viminfo
endif

set viewdir=~/.vim_backups/view

" Save cursor position, folds, and so on.
set viewoptions=cursor,folds,slash,unix
