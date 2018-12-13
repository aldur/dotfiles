if isdirectory($HOME . '/.vim/templates') == 0
    finish
endif

autocmd vimrc BufNewFile *.py 0r ~/.vim/templates/skeleton.py
autocmd vimrc BufNewFile *.gnuplot 0r ~/.vim/templates/skeleton.gnuplot
autocmd vimrc BufNewFile *.tex 0r ~/.vim/templates/skeleton.tex
autocmd vimrc BufNewFile *.sh 0r ~/.vim/templates/skeleton.sh
