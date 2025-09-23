include ../include.mk

DOTFILES = latexmkrc hammerspoon tmux.conf tmux-osx.conf hushlogin
TARGETS = $(DOTFILES) gpg-agent.conf scripts

.PHONY: $(TARGETS)
all: $(TARGETS)

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

scripts:
	$(LN) $(shell readlink -f scripts/com.github.aldur.remarkablepages.plist) ~/Library/LaunchAgents/com.github.aldur.remarkablepages.plist
	launchctl load -w ~/Library/LaunchAgents/com.github.aldur.remarkablepages.plist

gpg-agent.conf:
	mkdir -p ${HOME}/.gnupg
	echo pinentry-program /run/current-system/sw/bin/pinentry-mac >> ${HOME}/.gnupg/$@
