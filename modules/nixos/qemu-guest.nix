# Settings that all guests of `qemu-vm` (packages/qemu-vm) share. They are
# the disk layout, the serial console, a fixed SSH host key, auto-login,
# passwordless sudo, and the GitHub SSH keys. A guest adds what runs
# inside.
{
  config,
  inputs,
  lib,
  modulesPath,
  ...
}:
let
  cfg = config.aldur.qemuGuest;
in
{
  imports = [
    ../current_system_flake.nix

    # This is not technically required since the `vm-nogui` format already
    # imports this modules.
    # However, this way we can rebuild the NixOS image from
    # _within_ the VM.
    "${modulesPath}/virtualisation/qemu-vm.nix"
  ];

  options.aldur.qemuGuest.sshHostKeyDir = lib.mkOption {
    type = lib.types.path;
    description = ''
      Directory that holds `ssh_host_ed25519_key` and its `.pub` file.
      The guest only uses the key with the host, not on the network. A
      fixed key avoids a new fingerprint check for each new VM.
    '';
  };

  config = {
    environment.etc = {
      "ssh/ssh_host_ed25519_key" = {
        mode = "0600";
        source = "${cfg.sshHostKeyDir}/ssh_host_ed25519_key";
      };
      "ssh/ssh_host_ed25519_key.pub" = {
        mode = "0644";
        source = "${cfg.sshHostKeyDir}/ssh_host_ed25519_key.pub";
      };
    };

    users.users.${config.mainUser}.openssh.authorizedKeys.keys = inputs.self.utils.github-keys;

    services.getty.autologinUser = config.mainUser;
    security.sudo-rs.wheelNeedsPassword = false;

    # Overwrite since it does more harm than good
    # https://github.com/nix-community/nixos-generators/blob/
    # 032decf9db65efed428afd2fa39d80f7089085eb/formats/vm-nogui.nix#L20C3-L20C29
    environment.loginShellInit = lib.mkForce "";

    virtualisation = {
      # By default, `nix` mounts the whole /nix/store of the host to the VM.
      # That's insecure, since it might leak unrelated (to the vm) files.
      # This disables it, at the cost of building the /nix/store image at
      # runtime and increasing vm startup time.
      useNixStoreImage = true;

      # Make the nixStoreImage from above writable.
      writableStore = true;

      # No shared directories. The nixpkgs qemu on macOS has no 9p. Use
      # scp through the forwarded SSH port.
      sharedDirectories = lib.mkForce { };

      # Serial only by default. `qemu-vm --gui` adds the display devices.
      graphics = lib.mkDefault false;

      # No need for this device.
      qemu.virtioKeyboard = false;

      # ctrl-b, since ctrl-a clashes with `tmux`
      qemu.options = [ "-echr 0x02" ];
    };

    services.getty.helpLine = ''
      Type 'Ctrl-b c' from `bash` to switch to the QEMU console.
    '';
  };
}
