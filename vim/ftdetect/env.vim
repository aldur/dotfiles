" This will make `env` file inherit from `sh`, but with some additions.
" See ~/.vim/after/ftplugin/sh.vim and ~/.vim/after/ftplugin/env.vim
autocmd BufRead,BufNewFile *.env set filetype=sh.env
