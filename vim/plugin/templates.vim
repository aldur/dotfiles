if isdirectory($HOME . '/.vim/templates') == 0
    finish
endif

autocmd vimrc BufNewFile *.py keepalt 0r ~/.vim/templates/skeleton.py
autocmd vimrc BufNewFile *.gnuplot keepalt 0r ~/.vim/templates/skeleton.gnuplot
autocmd vimrc BufNewFile *.tex keepalt 0r ~/.vim/templates/skeleton.tex
autocmd vimrc BufNewFile *.sh keepalt 0r ~/.vim/templates/skeleton.sh
