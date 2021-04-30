include ../include.mk

DOTFILES = psqlrc radare2rc curlrc gdbinit inputrc ideavimrc chktexrc pylintrc gitignore_global gitattributes_global weechat mdlrc mdlstyle.rb ripgreprc
CONFIG_FILES = flake8 pycodestyle ctags fd
ALL = $(DOTFILES) $(CONFIG_FILES) _yamllint _bat vale git gpg.conf scdaemon.conf

.PHONY: $(ALL)
all: $(ALL)

git:
	git config --global user.name "Adriano Di Luzio"
	git config --global user.email "adrianodl@hotmail.it"
	git config --global commit.verbose true
	git config --global push.default current
	git config --global pull.default current
	git config --global push.followTags true
	git config --global core.excludesfile ~/.gitignore_global
	git config --global core.attributesfile ~/.gitattributes_global
	git config --global log.abbrevCommit true
	git config --global log.follow true
	git config --global status.showUntrackedFiles all
	git config --global pull.rebase true
	git config --global rebase.autoStash true
	git config --global commit.gpgsign true
	git config --global user.signingkey 22ABB9E8653C4764FF5B842B67F8D00BDD8874D3

$(DOTFILES):
	$(LN) $(shell readlink -f $@) ${HOME}/.$@

$(CONFIG_FILES):
	mkdir -p ${HOME}/.config/
	$(LN) $(shell readlink -f $@) ${HOME}/.config/$@

_yamllint: yamllint
	mkdir -p ${HOME}/.config/$</
	$(LN) $(shell readlink -f $<) ${HOME}/.config/$</config

_bat: bat
	mkdir -p ${HOME}/.config/$</
	$(LN) $(shell readlink -f $<) ${HOME}/.config/$</config

vale:
	$(MAKE) -C $@

gpg.conf scdaemon.conf:
	mkdir -p ${HOME}/.gnupg
	$(LN) $(shell readlink -f $@) ${HOME}/.gnupg/$@
