" Run tests from the file directory.
autocmd vimrc BufNewFile,BufRead */test_*.py setlocal makeprg=cd\ %:h\ &&\ pipenv\ run\ pytest\ -s\ %
