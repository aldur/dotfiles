# Dotfiles

A collection of my configuration / dotfiles.

## Requirements

Different platforms have different requirements.

### macOS

On MacOS, first install `homebrew`. Then:

```
$ brew install git make gpg coreutils git-crypt
$ PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
$ make requirements
```

### git-crypt

Some files of this repository have been encrypted.
Decrypt them with `git-crypt unlock` before running `make`.

## Install

Simply run `make` from the top-level directory.
