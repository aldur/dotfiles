# TODO: check for requirements. 

SUBDIRS = zsh vim various ssh

OS := $(shell uname)
ifeq ($(OS), Darwin)
	SUBDIRS += osx
else
	SUBDIRS += arch
endif

export LN = ln -sf

.PHONY: all $(SUBDIRS)

all: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@
