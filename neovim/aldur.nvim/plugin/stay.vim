" Replace the `vim-stay` plugin with this, which comes from the VIM runtime.
autocmd vimrc BufReadPost *
            \ if line("'\"") >= 1 && line("'\"") <= line("$") && &ft !~# 'commit'
            \ |   exe "normal! g`\""
            \ | endif
