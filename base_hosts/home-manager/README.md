# Standalone Home Manager

A user environment for non-NixOS Linux distributions.

Install Nix first, with `nix-command` and `flakes` enabled, and run these
commands as the existing `aldur` user whose home is `/home/aldur`:

```bash
# Build without activating; inspect result/activate and result/home-files.
nix build github:aldur/dotfiles#home

# Activate the user environment.
nix run github:aldur/dotfiles#home
```

The same commands work on x86-64 and ARM Linux.

The Home Manager CLI is also available, with explicit configuration selectors:

```bash
# x86-64
nix run home-manager/release-26.05 -- switch --flake github:aldur/dotfiles#aldur
# ARM
nix run home-manager/release-26.05 -- switch --flake github:aldur/dotfiles#aldur-aarch64
```

Home Manager's release matches this flake's Nixpkgs release, independently of
Ubuntu's version. If flakes are not enabled, add `--extra-experimental-features
'nix-command flakes'` immediately after `nix`.
