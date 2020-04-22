include ../include.mk

DOTFILES = colors dircolors
.PHONY: all

all: zsh theme oh $(DOTFILES)

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

zsh: zshrc
	$(LN) $(shell readlink -f zshrc) ${HOME}/.zshrc

theme:
	mkdir -p ${HOME}/.oh-my-zsh/custom/themes
	$(LN) $(shell readlink -f aldur.zsh-theme) ${HOME}/.oh-my-zsh/custom/themes/aldur.zsh-theme

oh:
	sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
