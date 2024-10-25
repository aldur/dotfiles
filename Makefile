include include.mk

TARGETS = neovim various ssh fish

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
TARGETS += osx
endif

all: $(TARGETS)
.PHONY: $(TARGETS) all

$(TARGETS):
	$(MAKE) -C $@
