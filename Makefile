include include.mk

# TODO: check for requirements.
TARGETS = vim various ssh fish zsh

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
TARGETS += osx

# This assumes that homebrew is installed.
requirements: homebrew ale_linters_fixers_and_lsp

homebrew: homebrew-cask universal-ctags
	brew install fzf ack diff-so-fancy fd zsh
	brew install tmux reattach-to-user-namespace
	brew install neovim curl
	brew install rig autossh pinentry-mac
	brew install npm gem

homebrew-cask: fira-code
	brew cask install 1password keybase skim tunnelblick android-platform-tools font-fontawesome mactex-no-gui skype vimr android-studio google-chrome plex slack vlc appcleaner plex-media-player spotify zoomus calibre hammerspoon tableplus cyberduck iterm2 pycharm the-unarchiver disk-inventory-x karabiner-elements sigil tor-browser

fira-code:
	brew tap homebrew/cask-fonts
	brew cask install font-fira-code

universal-ctags:
	brew install --HEAD universal-ctags/universal-ctags/universal-ctags

ale_linters_fixers_and_lsp: homebrew
	brew install jq libxml2 tidy-html5 pgformatter libxml2 shfmt texlab vale
	pip3 install pynvim black vim-vint python-language-server[all]
	gem install sqlint mdl
	npm install -g prettier@1.13

endif

all: $(TARGETS)
.PHONY: $(TARGETS) all

$(TARGETS):
	$(MAKE) -C $@
