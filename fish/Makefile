include ../include.mk

.PHONY: all fish
all: fish

fish: 
	mkdir -p ${HOME}/.config
	$(LN) $(shell readlink -f $@) ${HOME}/.config/$@
