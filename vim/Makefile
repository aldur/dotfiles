.PHONY: all vimrc ftplugin neovim templates

all: vimrc ftplugin neovim templates autload plugin after_ftplugin

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

ftplugin:
	mkdir -p ${HOME}/.vim/after/
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/$@

after_ftplugin:
	mkdir -p ${HOME}/.vim/after/
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/after/plugin

neovim:
	mkdir -p ${HOME}/.config
	$(LN) ${HOME}/.vim ${HOME}/.config/nvim
	$(LN) ${HOME}/.vimrc ${HOME}/.config/nvim/init.vim
