DOTFILES = gitignore_global psqlrc
CONFIG_FILES = flake8 pep8

.PHONY: all $(DOTFILES) $(CONFIG_FILES)

all: $(DOTFILES)

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

$(CONFIG_FILES):
	$(LN) $(shell readlink -f $@) ${HOME}/config/$@
