.PHONY: all vimrc ftplugin neovim templates

all: vimrc ftplugin neovim templates

vimrc:
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

templates:
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

ftplugin:
	mkdir -p ${HOME}/.vim/after/ftplugin/
	$(LN) $(shell readlink -f python.vim) ${HOME}/.vim/after/ftplugin/python.vim
	$(LN) $(shell readlink -f gnuplot.vim) ${HOME}/.vim/after/ftplugin/gnuplot.vim

neovim:
	mkdir -p ${HOME}/.config
	$(LN) ${HOME}/.vim ${HOME}/.config/nvim
	$(LN) ${HOME}/.vimrc ${HOME}/.config/nvim/init.vim
