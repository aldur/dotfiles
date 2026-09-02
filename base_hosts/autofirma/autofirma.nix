# VM plumbing for the AutoFirma guest; see guest.nix for what runs inside.
{
  inputs,
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    "${inputs.self}/modules/current_system_flake.nix"
    ./guest.nix

    # This is not technically required since the `vm-nogui` format already
    # imports this modules.
    # However, this way we can rebuild the NixOS image from
    # _within_ the VM.
    "${modulesPath}/virtualisation/qemu-vm.nix"
  ];

  environment.etc = {
    "ssh/ssh_host_ed25519_key" = {
      mode = "0600";
      source = ./ssh_host_ed25519_key;
    };
    "ssh/ssh_host_ed25519_key.pub" = {
      mode = "0644";
      source = ./ssh_host_ed25519_key.pub;
    };
  };

  # Overwrite since it does more harm than good
  # https://github.com/nix-community/nixos-generators/blob/
  # 032decf9db65efed428afd2fa39d80f7089085eb/formats/vm-nogui.nix#L20C3-L20C29
  environment.loginShellInit = lib.mkForce "";

  virtualisation = {
    # By default, `nix` mounts the whole /nix/store of the host to the VM.
    # That's insecure, since it might leak unrelated (to the vm) files.
    # This disables it, at the cost of building the /nix/store image at runtime
    # and increasing vm startup time.
    useNixStoreImage = true;

    # Make the nixStoreImage from above writable.
    writableStore = true;

    # No shared directories: the host qemu has no 9p on macOS. Move files
    # with scp through the forwarded SSH port instead.
    sharedDirectories = lib.mkForce { };

    # The display devices come from `qemu-vm --gui`.
    graphics = true;

    # ctrl-b, since ctrl-a clashes with `tmux`
    qemu.options = [ "-echr 0x02" ];
  };

  services.getty.helpLine = ''
    Type 'Ctrl-b c' from `bash` to switch to the QEMU console.
  '';
}
