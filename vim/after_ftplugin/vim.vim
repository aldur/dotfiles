" https://stackoverflow.com/questions/14385998/how-can-i-execute-the-current-line-as-vim-ex-commands/14386090
" The following turn any `vim` buffer behave like the command-line window
" i.e. by quickly executing lines with `<CR>` from normal mode.
"
" When selected through visual selections, the <bar> will be removed and lines
" will be joined.
nnoremap <silent><buffer> <CR> :execute getline(".")<cr>
vnoremap <silent><buffer> <CR> :<c-u>execute join(getline("'<","'>"),'<bar>')<cr>
