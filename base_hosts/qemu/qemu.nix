{
  inputs,
  config,
  ...
}:
{
  imports = [
    "${inputs.self}/modules/nixos/qemu-guest.nix"
    "${inputs.self}/modules/nixos/pragmatism.nix"
  ];

  aldur.qemuGuest.sshHostKeyDir = ./.;

  programs.aldur = {
    claude-code.enable = true;
    codex.enable = true;
  };

  networking.hostName = "qemu-nixos";

  environment = {
    sessionVariables = {
      TERM = "screen-256color";
    };
  };

  # Disable virtual console
  systemd.services."autovt@".enable = false;
  systemd.services."getty@".enable = false;

  home-manager.users.${config.mainUser} = _: {
    programs = {
      aldur.lazyvim.enable = true;
      git.settings.gpg.ssh.defaultKeyCommand = "sh -c 'echo key::$(ssh-add -L | grep -i sign)'";
      better-nix-search.enable = true;
    };
  };
}
