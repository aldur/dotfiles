.PHONY: all vimrc python.vim

all: vimrc python.vim

vimrc:
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

python.vim:
	mkdir -p ${HOME}/.vim/after/ftplugin/
	$(LN) $(shell readlink -f python.vim) ${HOME}/.vim/after/ftplugin/python.vim
