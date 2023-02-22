include ../include.mk

DOTFILES = latexmkrc hammerspoon tmux.conf tmux-osx.conf hushlogin
TARGETS = $(DOTFILES) gpg-agent.conf karabiner macos-preferences scripts

.PHONY: $(TARGETS)
all: $(TARGETS)

$(DOTFILES):
	touch .hushlogin
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

karabiner:
	mkdir -p ${HOME}/.config
	$(LN) $(shell readlink -f karabiner) ${HOME}/.config/karabiner

scripts:
	$(LN) $(shell readlink -f scripts/com.github.aldur.remarkablepages.plist) ~/Library/LaunchAgents/com.github.aldur.remarkablepages.plist
	launchctl load -w ~/Library/LaunchAgents/com.github.aldur.remarkablepages.plist

gpg-agent.conf:
	# This needs to be dynamic because we read brew's prefix
	mkdir -p ${HOME}/.gnupg
	echo pinentry-program $(shell brew --prefix)/bin/pinentry-mac >> ${HOME}/.gnupg/$@

macos-preferences:
	# Faster dock autohide
	defaults write com.apple.dock autohide-delay -float 0
	defaults write com.apple.dock autohide-time-modifier -float 0.15
	killall Dock

	# This needs logging out and in
	defaults write -g InitialKeyRepeat -int 10
	defaults write -g KeyRepeat -int 1
