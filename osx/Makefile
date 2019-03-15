DOTFILES = latexmkrc hammerspoon tmux.conf zprofile zshrc.local tmux-osx.conf hushlogin

.PHONY: all $(DOTFILES) karabiner gpg-agent

all: $(DOTFILES) karabiner gpg-agent

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

karabiner:
	mkdir -p ${HOME}/.config
	$(LN) $(shell readlink -f karabiner) ${HOME}/.config/karabiner

gpg-agent:
	mkdir -p ${HOME}/.gnupg
	$(LN) $(shell readlink -f gpg-agent.conf) ${HOME}/gpg-agent.conf

