# Dotfiles

A collection of my configuration / dotfiles.

## Requirements

Different platforms have different requirements.
On MacOS, first install homebrew. 
Then:

```
$ brew install git make gpg coreutils git-crypt fzf ack diff-so-fancy fd zsh weechat tmux reattach-to-user-namespace rig neovim python curl autossh ctags pinentry-mac
$ PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
```

## Install

Simply run `make` from the top-level directory.

## git-crypt

Some files of this repository have been encrypted.
Decrypt them with `git-crypt unlock` before running `make`.
