{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.nixos-avf.nixosModules.avf
    "${inputs.self}/modules/current_system_flake.nix"
  ];

  networking.hostName = "avf-nixos";
  system.stateVersion = "26.05";

  # The Terminal app opens a session for this user through ttyd.
  avf.defaultUser = config.mainUser;

  # Runs in the stock Debian guest and replaces its disk with this image.
  # No root and no debuggable Android build are necessary.
  avf.extraFiles."replace.sh" = "${inputs.nixos-avf}/initial/replace.sh";

  # The user has no password: ttyd logs in with `login -f`. As in the qemu
  # guests, the VM boundary and the phone lock screen protect the account.
  users.users.${config.mainUser}.initialHashedPassword = lib.mkForce null;
  users.allowNoPasswordLogin = true;
  security.sudo-rs.wheelNeedsPassword = false;

  # nixos-avf applies arm64-balloon.patch from this AOSP source, but its last
  # patch does not apply on Linux 6.1.188 and later. Rebase it in the source.
  # Remove this overlay when nixos-avf has a fix.
  nixpkgs.overlays = [
    (final: prev: {
      fetchgit = prev.fetchgit // {
        __functor =
          _: args:
          if args.url or null == "https://android.googlesource.com/platform/packages/modules/Virtualization/" then
            final.applyPatches {
              src = prev.fetchgit args;
              patches = [ ./arm64-balloon-6.1.188.patch ];
            }
          else
            prev.fetchgit args;
      };
    })
  ];

  home-manager.users.${config.mainUser}.home.packages = [
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.lazyvim-light
  ];
}
