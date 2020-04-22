# Makefile configuration
SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

# We need make 3.82 that implements undefines and .SHELLFLAGS
ifeq ($(filter undefine,$(value .FEATURES)),)
$(error Unsupported Make version. \
    The build system does not work properly with GNU Make $(MAKE_VERSION), \
    please use GNU Make 3.82 or above.)
endif

# on macOS we set the shell to zsh
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
SHELL := zsh
.SHELLFLAGS += --nullglob
endif

LN := ln -sfT

