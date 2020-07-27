# Dotfiles

A collection of my configuration / dotfiles.

## Requirements

Different platforms have different requirements.

### git-crypt

Some files of this repository have been encrypted.
Decrypt them with `git-crypt unlock` before running `make`.

### macOS

On macOS, first install `homebrew`. Then:

```bash
$ git clone https://github.com/aldur/dotfiles .dotfiles
$ brew install git make gpg coreutils git-crypt
$ PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
$ gpg --import email.gpg
$ git-crypt unlock
$ make requirements #optional
```

## Install

Simply run `make` from the top-level directory.

```bash
$ make
```
