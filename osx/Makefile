DOTFILES = latexmkrc tmux.conf zprofile zshrc.local

.PHONY: all $(DOTFILES)

all: $(DOTFILES)

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@
