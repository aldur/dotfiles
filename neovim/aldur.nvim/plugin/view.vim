if isdirectory($HOME . '/.vim_backups') == 0
    call mkdir($HOME . '/.vim_backups', 'p')
endif

" Tell (n)vim to remember certain things when we exit
"  'x:  marks will be remembered for up to x previously edited files
"  "y (or <y for nvim):  will save up to y lines for each register
"  %    :  saves and restores the buffer list
"  n... :  where to save the viminfo files
set shada='250,<100,%,n~/.vim_backups/nviminfo

set viewdir=~/.vim_backups/view

" Save cursor position, folds, and so on.
set viewoptions=cursor,folds,slash,unix
