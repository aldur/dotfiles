# Standalone Home Manager

A user environment for non-NixOS Linux distributions.

## As user `aldur`

Install Nix first, with `nix-command` and `flakes` enabled, and run these
commands:

```bash
# Build without activating; inspect result/activate and result/home-files.
nix build github:aldur/dotfiles#home

# Activate the user environment.
nix run github:aldur/dotfiles#home
```

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

## As a different user

The bootstrap script below supports Ubuntu **24.04 LTS** and an existing
non-root account (with sudo access).

```bash
curl -fsSL https://raw.githubusercontent.com/aldur/dotfiles/master/base_hosts/home-manager/bootstrap.sh | bash
```

### Changes and updates

Edit `~/.config/home-manager/host.json` for account settings and
`~/.config/home-manager/flake.nix` to customize the build:

```nix
home = dotfiles.lib.mkHome (host // {
  modules = [
    {
      programs.aldur.codex.enable = true;
    }
  ];
});
```
