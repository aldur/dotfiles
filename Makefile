# TODO: check for requirements.
TARGETS = vim various ssh fish zsh 

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
TARGETS += osx
endif

all: $(TARGETS)
.PHONY: $(TARGETS) all

$(TARGETS):
	$(MAKE) -C $@
