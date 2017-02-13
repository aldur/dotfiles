DOTFILES = latexmkrc hammerspoon tmux.conf zprofile zshrc.local tmux-osx.conf

.PHONY: all $(DOTFILES)

all: $(DOTFILES) karabiner

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

karabiner:
	$(LN) $(shell readlink -f karabiner) ${HOME}/.config/karabiner
