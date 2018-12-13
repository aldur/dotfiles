" Tell (n)vim to remember certain things when we exit
"  '100  :  marks will be remembered for up to 100 previously edited files
"  "100 :  will save up to 100 lines for each register
"  <100 :  will save up to 100 lines for each register (new alternative to ")
"  :1000  :  up to 1000 lines of command-line history will be remembered
"  %    :  saves and restores the buffer list
"  n... :  where to save the viminfo files
if has('nvim')
    set shada='100,<100,:10000,%,n~/.nvim/nviminfo
    set viewdir=~/.vim/view
else
    set viminfo='100,\"100,:10000,%,n~/.vim/viminfo
endif

" Save cursor position, folds, and so on.
set viewoptions=cursor,folds,slash,unix
