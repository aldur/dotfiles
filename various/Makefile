DOTFILES = psqlrc radare2rc curlrc gdbinit ctags inputrc ideavimrc chktexrc pylintrc gitignore_global
CONFIG_FILES = flake8 pep8

.PHONY: all git $(DOTFILES) $(CONFIG_FILES)

all: $(DOTFILES) $(CONFIG_FILES) git

git: 
	git config --global user.name "Adriano Di Luzio"
	git config --global user.email "adrianodl@hotmail.it"
	git config --global commit.verbose true
	git config --global push.default current
	git config --global push.followTags true
	git config --global core.excludesfile ~/.gitignore_global
	git config --global log.abbrevCommit true
	git config --global log.follow true
	git config --global status.showUntrackedFiles all
	git config --global pull.rebase true
	git config --global rebase.autoStash true

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

$(CONFIG_FILES):
	mkdir -p ${HOME}/.config/
	$(LN) $(shell readlink -f $@) ${HOME}/.config/$@
