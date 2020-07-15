include ../include.mk

DOTFILES = colors dircolors
.PHONY: all

all: zsh $(DOTFILES)

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

zsh: zshrc
	$(LN) $(shell readlink -f zshrc) ${HOME}/.zshrc
