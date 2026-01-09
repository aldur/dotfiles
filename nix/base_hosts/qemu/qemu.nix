{
  config,
  inputs,
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    "${inputs.self}/modules/current_system_flake.nix"
    "${inputs.self}/modules/nixos/pragmatism.nix"

    # This is not technically required since the `vm-nogui` format already
    # imports this modules.
    # However, this way we can rebuild the NixOS image from
    # _within_ the VM.
    "${modulesPath}/virtualisation/qemu-vm.nix"
  ];

  programs = {
    aldur = {
      lazyvim.enable = true;
      lazyvim.packageNames = [ "lazyvim" ];

      claude-code.enable = true;
    };

  };

  networking.hostName = "qemu-nixos";

  services.getty.autologinUser = config.users.users.aldur.name;
  security.sudo-rs.wheelNeedsPassword = false;

  environment = {
    sessionVariables = {
      TERM = "screen-256color";
    };
  };

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

  # Disable virtual console
  systemd.services."autovt@".enable = false;
  systemd.services."getty@".enable = false;

  # Overwrite since it does more harm than good
  # https://github.com/nix-community/nixos-generators/blob/
  # 032decf9db65efed428afd2fa39d80f7089085eb/formats/vm-nogui.nix#L20C3-L20C29
  environment.loginShellInit = lib.mkForce "";

  home-manager.users.aldur = _: {
    programs = {
      git.settings.gpg.ssh.defaultKeyCommand = "sh -c 'echo key::$(ssh-add -L | grep -i sign)'";
      better-nix-search.enable = true;
    };
  };

  users.users.aldur.openssh.authorizedKeys.keys = inputs.self.utils.github-keys;

  virtualisation = {
    # By default, `nix` mounts the whole /nix/store of the host to the VM.
    # That's insecure, since it might leak unrelated (to the vm) files.
    # This disables it, at the cost of building the /nix/store image at runtime
    # and increasing vm startup time.
    useNixStoreImage = true;

    # Make the nixStoreImage from above writable.
    writableStore = true;

    # No shared directories.
    sharedDirectories = lib.mkForce { };

    # No graphics either.
    graphics = false;

    # No need for this device.
    qemu.virtioKeyboard = false;

    # ctrl-b, since ctrl-a clashes with `tmux`
    qemu.options = [ "-echr 0x02" ];
  };

  services.getty.helpLine = ''
    Type 'Ctrl-b c' from `bash` to switch to the QEMU console.
  '';

}
