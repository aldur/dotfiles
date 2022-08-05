include ../include.mk

DOTFILES = latexmkrc hammerspoon tmux.conf tmux-osx.conf hushlogin
TARGETS = $(DOTFILES) gpg-agent.conf karabiner

.PHONY: $(TARGETS)
all: $(TARGETS)

$(DOTFILES):
	touch .hushlogin
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

karabiner:
	mkdir -p ${HOME}/.config
	$(LN) $(shell readlink -f karabiner) ${HOME}/.config/karabiner

gpg-agent.conf:
	# This needs to be dynamic because we read brew's prefix
	mkdir -p ${HOME}/.gnupg
	echo pinentry-program $(shell brew --prefix)/bin/pinentry-mac >> ${HOME}/.gnupg/$@

