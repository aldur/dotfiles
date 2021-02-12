" This will make `env` file inherit from `sh`, but with some additions.
" See ~/.vim/after/ftplugin/sh.vim and ~/.vim/after/ftplugin/env.vim
" Source: https://www.reddit.com/r/vim/comments/8fmntk/is_there_a_way_to_alias_one_file_type_for_another/
autocmd vimrc BufRead,BufNewFile *.env set filetype=sh.env
