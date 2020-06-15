include ../include.mk

.PHONY: all
all: vale styles link

vale:
	curl -sfL https://install.goreleaser.com/github.com/ValeLint/vale.sh | sh -s latest

styles:
	mkdir -p styles
	cd styles; curl -L https://raw.githubusercontent.com/errata-ai/styles/master/library.json | jq '.[].url' | xargs -n 1 curl -LO
	cd styles; unzip \*.zip
	rm styles/*.zip

link:
	$(LN) $(shell readlink -f vale.ini) ${HOME}/.vale.ini
	mkdir -p ~/.vale/
	$(LN) $(shell readlink -f bin) ${HOME}/.vale/bin
	$(LN) $(shell readlink -f styles) ${HOME}/.vale/styles
