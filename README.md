# Dotfiles

A collection of my configuration / dotfiles.

## Requirements

Different platforms have different requirements.

### git-crypt

Some files of this repository have been encrypted.
Decrypt them with `git-crypt unlock <symmetric_key>` before running `make`.

### macOS

On macOS, first install `homebrew`. Then:

```bash
$ git clone https://github.com/aldur/dotfiles .dotfiles
$ brew install git make gpg coreutils git-crypt
$ PATH="$(brew --prefix)/opt/coreutils/libexec/gnubin:$PATH"
$ git-crypt unlock <symmetric_key>
$ gmake requirements #optional
```

## Install

Simply run `make` from the top-level directory.

```bash
$ make
```

## Running `neovim` through `nix`

```bash
nix run "git+https://github.com/aldur/dotfiles?ref=vim_nix&dir=vim"
```

