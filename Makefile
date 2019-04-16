# TODO: check for requirements.

SUBDIRS = zsh vim various ssh

OS := $(shell uname)
ifeq ($(OS), Darwin)
	SUBDIRS += osx
else
	SUBDIRS += arch
endif

export LN = ln -sfT

.PHONY: all $(SUBDIRS) weechat

all: $(SUBDIRS) weechat

$(SUBDIRS):
	$(MAKE) -C $@

weechat:
	$(LN) $(shell readlink -f weechat) ${HOME}/.weechat

