DOTFILES = psqlrc pdbrc radare2rc pythonrc pdbrc.py curlrc gdbinit ctags inputrc
CONFIG_FILES = flake8 pep8 

.PHONY: all gitignore $(DOTFILES) $(CONFIG_FILES)

all: $(DOTFILES) gitignore

gitignore: gitignore_global
	$(LN) $(shell readlink -f $gitignore_global) ${HOME}/.$gitignore_global
	git config --global core.excludesfile ~/.gitignore_global

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

$(CONFIG_FILES):
	$(LN) $(shell readlink -f $@) ${HOME}/config/$@
