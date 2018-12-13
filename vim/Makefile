.PHONY: all vimrc ftplugin neovim templates

all: vimrc ftplugin neovim templates

vimrc:
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

templates:
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

plugin:
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

autoload:
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

ftplugin:
	$(LN) $(shell readlink -f $@) ${HOME}/.vim/$@

neovim:
	mkdir -p ${HOME}/.config
	$(LN) ${HOME}/.vim ${HOME}/.config/nvim
	$(LN) ${HOME}/.vimrc ${HOME}/.config/nvim/init.vim
