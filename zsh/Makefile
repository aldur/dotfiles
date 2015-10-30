.PHONY: all zsh theme

all: zsh theme
	
zsh: zshrc
	$(LN) $(shell readlink -f zshrc) ${HOME}/.zshrc

theme:
	mkdir -p ${HOME}/.oh-my-zsh/custom/themes
	$(LN) $(shell readlink -f aldur.zsh-theme) ${HOME}/.oh-my-zsh/custom/themes
