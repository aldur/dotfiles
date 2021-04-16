if executable('pipenv')
    " Run tests from the file directory.
    " Overrides makeprg in .dotfiles/vim/after_ftplugin/python.vim
    autocmd vimrc BufNewFile,BufRead */test_*.py setlocal makeprg=cd\ %:h\ &&\ pipenv\ run\ pytest\ -s\ %
endif
