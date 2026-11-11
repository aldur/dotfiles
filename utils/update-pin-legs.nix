# Turns discovered pins into a CI bump matrix, consumed by
# .github/workflows/update-pinned-packages.yml.
#
{ lib }:

{
  # Discovered pins per platform, from utils/discover-pins.nix. A package is
  # bumped on the platform that exposes it.
  linux,
  darwin ? [ ],
  # The GitHub runner labels the workflow schedules the legs on.
  runners ? {
    linux = "ubuntu-26.04";
    darwin = "macos-26";
  },
  # With `days` set, a leg takes only upstream states that are at least that
  # old. `exemptOwners` are GitHub owners that you trust.
  cooldown ? { },
}:

let
  byPath = platform: lib.listToAttrs (map (e: lib.nameValuePair e.path e) platform);
  linuxByPath = byPath linux;
  darwinByPath = byPath darwin;

  preferDarwin =
    path:
    (darwinByPath.${path} or null) != null
    && darwinByPath.${path}.source == "packages"
    && (linuxByPath.${path} or { source = "overlay"; }).source != "packages";

  # `os` names the platform in `uname -s` terms. It travels with the runner
  # so consumers (the local `update-pins` app) do not re-derive it from the
  # runner's name.
  onDarwin = e: e // { runner = runners.darwin; os = "Darwin"; };
  onLinux = e: e // { runner = runners.linux; os = "Linux"; };

  chosen =
    lib.mapAttrsToList (
      path: e: if preferDarwin path then onDarwin darwinByPath.${path} else onLinux e
    ) linuxByPath
    ++ map onDarwin (lib.filter (e: !(linuxByPath ? ${e.path})) darwin);

  cooldownDays = cooldown.days or 0;
  exemptOwners = map lib.toLower (cooldown.exemptOwners or [ ]);

  # What packages/update-pins/cooldown.py needs to find the age of an
  # upstream state.
  cooldownFor =
    e:
    let
      inherit (e.drv) src;
      url = src.url or (lib.head (src.urls or [ "" ]));
      asset = builtins.match "https://github.com/([^/]+)/([^/]+)/releases/download/([^/]+)/.*" url;
      github =
        if src ? owner && src ? repo && lib.hasInfix "github.com/" url then
          {
            inherit (src) owner repo rev;
            tag = src.tag or null;
          }
        else if asset != null then
          {
            owner = lib.elemAt asset 0;
            repo = lib.elemAt asset 1;
            rev = lib.elemAt asset 2;
            tag = lib.elemAt asset 2;
          }
        else
          null;
      common = {
        days = cooldownDays;
        args = e.pin.args or "";
        inherit (e.drv) version;
      };
    in
    if cooldownDays == 0 || !(e.pin.cooldown or true) then
      null
    else if github != null then
      if lib.elem (lib.toLower github.owner) exemptOwners then
        null
      else
        common // github // { type = "github"; }
    else if lib.hasPrefix "mirror://pypi/" url || lib.hasPrefix "https://files.pythonhosted.org/" url then
      common
      // {
        type = "pypi";
        # The project is the directory that holds the file.
        name = lib.last (lib.init (lib.splitString "/" url));
      }
    else
      # cooldown.py stops this leg. The other legs continue.
      common
      // {
        type = "unknown";
        inherit url;
      };

  leg = e: {
    inherit (e) runner os;
    cooldown = cooldownFor e;
    # `lazyvim.plugins.foo` becomes the leg `foo`; the branch, PR and artifact
    # are named after it.
    package = e.name;
    # The full bump command. CI and the local `update-pins` app run this
    # string verbatim, so the command has one source.
    #
    # nix-update's `--test` dies outright on a package with no
    # `passthru.tests`, so it is only requested when tests exist; a package
    # gaining tests still picks it up without touching the workflow.
    bump = lib.concatStringsSep " " (
      [ "nix run nixpkgs#nix-update -- --flake" ]
      ++ lib.optional ((e.drv.passthru.tests or { }) != { }) "--test"
      ++ lib.optional ((e.pin.args or "") != "") e.pin.args
      ++ [ e.path ]
    );
    # Building a passthru derivation on its own often proves little — a Neovim
    # plugin is just Lua copied into the store — so the default builds whatever
    # top-level package it reaches the tree through.
    verify = e.pin.verify or "nix build .#${e.root}";
  };

  bumped = lib.filter (e: !(e.pin ? exempt)) chosen;

  # nix-update finds a package in `packages.<system>`, then at the flake
  # root. It does not read the overlay. A leg for a package that only the
  # overlay has fails on the runner. The error is `expected a set but found
  # null`.
  #
  # This test is here, and not in checks/pinned-packages.nix, because only
  # this file sees the two platforms. A darwin-only package is in the overlay
  # on Linux, but the flake exports it on the runner that bumps it.
  unresolvable = lib.filter (e: e.source == "overlay") bumped;
in

lib.throwIf (unresolvable != [ ]) (
  "update pins:\n  "
  + lib.concatStringsSep "\n  " (
    map (
      e: "`${e.path}` is bumped on ${e.runner}, where only the overlay defines `${e.root}`"
    ) unresolvable
  )
  + "\n\n  nix-update resolves it through the flake's outputs, so export it from"
  + " `packages` (or reach it through the `passthru` of one that is exported)."
) (map leg bumped)
