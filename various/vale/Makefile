include ../../include.mk

.PHONY: all
all: styles

styles:
	mkdir -p styles
	cd styles; curl -L https://raw.githubusercontent.com/errata-ai/styles/master/library.json | jq '.[].url' | xargs -n 1 curl -LO
	cd styles; unzip \*.zip
	rm styles/*.zip

link: styles
	$(LN) $(shell readlink -f vale.ini) ${HOME}/.vale.ini
	mkdir -p ~/.vale/
	$(LN) $(shell readlink -f styles) ${HOME}/.vale/styles
