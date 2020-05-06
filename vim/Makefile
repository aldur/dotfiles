include ../include.mk

.PHONY: all
all: vimrc neovim templates autoload plugin after_plugin after_ftplugin scripts rplugin

vimrc:
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

scripts templates plugin rplugin: vimf
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

after_ftplugin: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/ftplugin

after_plugin: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/plugin

neovim: vimf vimrc
	mkdir -p ${HOME}/.config
	$(LN) ${HOME}/.vim ${HOME}/.config/nvim
	$(LN) ${HOME}/.vimrc ${HOME}/.config/nvim/init.vim

after: vimf
	mkdir -p ${HOME}/.vim/after

autoload: vimf
	mkdir -p ${HOME}/.vim/autoload

vimf:
	mkdir -p ${HOME}/.vim

