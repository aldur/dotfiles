" https://stackoverflow.com/questions/14385998/how-can-i-execute-the-current-line-as-vim-ex-commands/14386090
" The following turn any `vim` buffer behave like the command-line window
" i.e. by quickly executing lines with `<CR>` from normal mode.
"
" When selected through visual selections, the <bar> will be added between the
" joined lines
"
" Ignore if in command-line window
if getcmdwintype() ==# ''
    nnoremap <silent><buffer> <CR> :echomsg 'Line "' . getline(".") . '" executed' <bar> :execute getline(".")<cr>
    vnoremap <silent><buffer> <CR> :<c-u>execute join(getline("'<","'>"),'<bar>')<cr>

    " Same mapping as `vim-dispatch`
    nnoremap <silent><buffer> m<CR> :<c-u>Runtime<CR>
endif
