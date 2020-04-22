# TODO: check for requirements.
TARGETS = zsh vim various ssh weechat vale

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
TARGETS += osx
endif

.PHONY: all
all: $(TARGETS)

$(TARGETS):
	$(MAKE) -C $@
