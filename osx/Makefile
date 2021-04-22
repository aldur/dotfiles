include ../include.mk

DOTFILES = latexmkrc hammerspoon tmux.conf tmux-osx.conf hushlogin zprofile zshrc.local
TARGETS = $(DOTFILES) gpg-agent.conf karabiner

.PHONY: $(TARGETS)
all: $(TARGETS)

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

karabiner:
	mkdir -p ${HOME}/.config
	$(LN) $(shell readlink -f karabiner) ${HOME}/.config/karabiner

gpg-agent.conf:
	mkdir -p ${HOME}/.gnupg
	$(LN) $(shell readlink -f $@) ${HOME}/.gnupg/$@

