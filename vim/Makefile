include ../include.mk

.PHONY: all
all: vimrc neovim templates autoload aldur plugin ftdetect after_plugin after_ftplugin after_syntax after_indent scripts rplugin snippets 

vimrc:
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

scripts templates plugin rplugin ftdetect snippets: vimf
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

after_ftplugin: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/ftplugin

after_plugin: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/plugin

after_indent: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/indent

after_syntax: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/syntax

neovim: vimf vimrc
	mkdir -p ${HOME}/.config
	$(LN) ${HOME}/.vim ${HOME}/.config/nvim
	$(LN) ${HOME}/.vimrc ${HOME}/.config/nvim/init.vim

after: vimf
	mkdir -p ${HOME}/.vim/after

aldur: autoload
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/autoload/aldur

autoload: vimf
	mkdir -p ${HOME}/.vim/autoload

vimf:
	mkdir -p ${HOME}/.vim

