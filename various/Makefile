include ../include.mk

DOTFILES = psqlrc radare2rc curlrc gdbinit inputrc ideavimrc chktexrc pylintrc gitignore_global gitattributes_global weechat mdlrc mdlstyle.rb ripgreprc solhint.json
CONFIG_FILES = flake8 pycodestyle ctags fd marksman nix
ALL = $(DOTFILES) $(CONFIG_FILES) _yamllint _bat vale git gpg.conf scdaemon.conf

.PHONY: $(ALL)
all: $(ALL)

git:
	git config --global user.name "Adriano Di Luzio"
	git config --global user.email "adrianodl@hotmail.it"
	git config --global commit.verbose true
	git config --global push.default current
	git config --global push.autoSetupRemote true
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
	git config --global tag.gpgsign true
	git config --global tag.forceSignAnnotated true
	git config --global gpg.ssh.defaultKeyCommand 'sh -c \'echo key::$(ssh-add -L)\''
	git config --global rerere.enabled true
	git config --global rerere.autoUpdate true
	# https://blog.gitbutler.com/git-tips-2-new-stuff-in-git/
	git config --global column.ui auto
	git config --global branch.sort -committerdate
	# https://jvns.ca/blog/2024/02/16/popular-git-config-options/
	git config --global merge.conflictStyle zdiff3
	git config --global diff.algorithm histogram
	git config --global --add url.git@github.com:.insteadOf https://github.com/
	git config --global transfer.fsckobjects true
	git config --global fetch.fsckobjects true
	git config --global receive.fsckObjects true
	git config --global branch.sort -committerdate

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
