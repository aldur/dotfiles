DOTFILES = latexmkrc hammerspoon tmux.conf zprofile zshrc.local tmux-osx.conf hushlogin

.PHONY: all $(DOTFILES) karabiner

all: $(DOTFILES) karabiner

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

karabiner:
	mkdir -p ${HOME}/.config
	$(LN) $(shell readlink -f karabiner) ${HOME}/.config/karabiner
