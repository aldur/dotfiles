include include.mk

TARGETS = vim various ssh fish

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
TARGETS += osx

all: $(TARGETS)
.PHONY: $(TARGETS) all

$(TARGETS):
	$(MAKE) -C $@
