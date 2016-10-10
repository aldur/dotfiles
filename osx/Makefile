DOTFILES = latexmkrc hammerspoon tmux.conf zprofile zshrc.local tmux-osx.conf karabiner.d

.PHONY: all $(DOTFILES)

all: $(DOTFILES)

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@
