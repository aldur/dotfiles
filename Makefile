# TODO: check for requirements. 

SUBDIRS = zsh osx vim various

export LN = ln -sf

.PHONY: all $(SUBDIRS)

all: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@
