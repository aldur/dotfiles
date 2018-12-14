.PHONY: all neovim templates autoload plugin after_plugin after_ftplugin

all: vimrc neovim templates autoload plugin after_plugin after_ftplugin

vimrc:
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

templates:
	mkdir -p ${HOME}/.vim
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

plugin:
	mkdir -p ${HOME}/.vim
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

autoload:
	mkdir -p ${HOME}/.vim
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

after_ftplugin:
	mkdir -p ${HOME}/.vim/after/
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/ftplugin

after_plugin:
	mkdir -p ${HOME}/.vim/after/
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/plugin

neovim:
	mkdir -p ${HOME}/.config
	$(LN) ${HOME}/.vim ${HOME}/.config/nvim
	$(LN) ${HOME}/.vimrc ${HOME}/.config/nvim/init.vim
