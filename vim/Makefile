.PHONY: all vimrc python.vim neovim

all: vimrc python.vim neovim

vimrc:
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

python.vim:
	mkdir -p ${HOME}/.vim/after/ftplugin/
	$(LN) $(shell readlink -f python.vim) ${HOME}/.vim/after/ftplugin/python.vim

neovim:
	mkdir -p ${HOME}/.config
	$(LN) ${HOME}/.vim ${HOME}/.config/nvim
	$(LN) ${HOME}/.vimrc ${HOME}/.config/nvim/init.vim
