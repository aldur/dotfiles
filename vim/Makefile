include ../include.mk

.PHONY: all
all: vimrc neovim templates autoload aldur plugin ftdetect after_plugin after_ftplugin after_syntax after_indent after_compiler after_queries scripts rplugin snippets UltiSnips ale_linters compiler lua

vimrc scripts templates plugin rplugin ftdetect snippets UltiSnips ale_linters compiler lua: vimf
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

after_ftplugin: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/ftplugin

after_plugin: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/plugin

after_indent: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/indent

after_syntax: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/syntax

after_compiler: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/compiler

after_queries: after
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/queries

neovim: vimf vimrc
	mkdir -p ${HOME}/.config
	$(LN) ${HOME}/.vim ${HOME}/.config/nvim
	$(LN) ${HOME}/.vim/vimrc ${HOME}/.config/nvim/init.vim

after: vimf
	mkdir -p ${HOME}/.vim/after

aldur: autoload
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/autoload/aldur

autoload: vimf
	mkdir -p ${HOME}/.vim/autoload

vimf:
	mkdir -p ${HOME}/.vim

