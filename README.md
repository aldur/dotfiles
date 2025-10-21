# Dotfiles

My collection of dotfiles.

## Structure

These dotfiles are currently arranged around two configuration systems:

1. `nix`-based: how I lately started configuring [throwaway containers and VMs](https://aldur.blog/articles/2025/06/19/nixos-in-crostini).
1. `Makefile`-based: how have I historically configured my systems, mostly on
   macOS.

Over time, I will slowly migrate away from `Makefile`s, deleting what is not
relevant anymore.

## With `nix`

The `nix` folder includes a few NixOS/`nix-darwin` modules, some general Nix
packages, and shared Nix configurations (e.g., for `home-manager`).

It doesn't include host-specific configuration, leaving that to a Nix Flakes
that pulls [./nix/flake.nix] as an input.

Most NixOS modules assume the username to be `aldur`.

### Templates

#### QEMU VM

```bash
nix flake init --template github:aldur/dotfiles?dir=nix#vm-nogui
```

### Packages

#### `lazyvim`

A slightly customized [LazyVim setup](https://www.lazyvim.org).

```bash
nix run "github:aldur/dotfiles?dir=nix#lazyvim"
```

Or its light version:

```bash
nix run "github:aldur/dotfiles?dir=nix#lazyvim-light"
```

#### `neovim`

My (previous) `nvim` setup. Technically is its own Flake.

```bash
nix run "github:aldur/dotfiles?dir=nix#nvim"
```

## Makefile

### Install

Simply run `make` from the top-level directory.

```bash
make
```

### Requirements

Different systems have different requirements that `make` will try to handle
for you.

#### git-crypt

Some files in this repository have been encrypted.

To decrypt them, run `git-crypt unlock <symmetric_key>` before running `make`.

#### macOS

On macOS, first install `homebrew`. Then:

```bash
git clone https://github.com/aldur/dotfiles .dotfiles
brew install git make gpg coreutils git-crypt
PATH="$(brew --prefix)/opt/coreutils/libexec/gnubin:$PATH"
git-crypt unlock <symmetric_key>
gmake requirements #optional
```
