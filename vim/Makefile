.PHONY: all vimrc ftplugin neovim templates

all: vimrc ftplugin neovim templates

vimrc:
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

templates:
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

ftplugin:
	mkdir -p ${HOME}/.vim/after/ftplugin/
	$(LN) $(shell readlink -f gitcommit.vim) ${HOME}/.vim/after/ftplugin/gitcommit.vim
	$(LN) $(shell readlink -f gnuplot.vim) ${HOME}/.vim/after/ftplugin/gnuplot.vim
	$(LN) $(shell readlink -f go.vim) ${HOME}/.vim/after/ftplugin/go.vim
	$(LN) $(shell readlink -f markdown.vim) ${HOME}/.vim/after/ftplugin/markdown.vim
	$(LN) $(shell readlink -f md.vim) ${HOME}/.vim/after/ftplugin/md.vim
	$(LN) $(shell readlink -f python.vim) ${HOME}/.vim/after/ftplugin/python.vim
	$(LN) $(shell readlink -f tex.vim) ${HOME}/.vim/after/ftplugin/tex.vim

neovim:
	mkdir -p ${HOME}/.config
	$(LN) ${HOME}/.vim ${HOME}/.config/nvim
	$(LN) ${HOME}/.vimrc ${HOME}/.config/nvim/init.vim
