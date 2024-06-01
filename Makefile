include include.mk

# TODO: check for requirements.
TARGETS = vim various ssh fish

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
TARGETS += osx

# This assumes that homebrew is installed.
requirements: homebrew ale_linters_fixers_and_lsp

homebrew:
	brew bundle install --file osx/Brewfile

homebrew-cask-heavy:
	brew bundle install --file osx/HeavyBrewfile

ale_linters_fixers_and_lsp: homebrew
	brew bundle install --file osx/AleBrewfile
	python3 -m pip install -U --break-system-packages -r various/ale_requirements.txt
	cat various/gem_ale_requirements.txt | xargs gem install --user-install
	cat various/npm_ale_requirements.txt | xargs npm install -g
	cat various/luarocks_requirements.txt | xargs -I '{}' luarocks install --server=https://luarocks.org/dev {}

pandoc_filters: homebrew
	cat various/gem_pandoc_requirements.txt | xargs gem install --user-install
endif

all: $(TARGETS)
.PHONY: $(TARGETS) all

$(TARGETS):
	$(MAKE) -C $@
