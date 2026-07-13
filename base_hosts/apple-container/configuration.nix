{ inputs, lib, ... }:
{
  imports = [
    ./apple-container.nix
    "${inputs.self}/modules/nixos/pragmatism.nix"
  ];

  users.users.aldur.openssh.authorizedKeys.keys = inputs.self.utils.github-keys;

  virtualisation.appleContainer = {
    # Literal, not `config.users.users.aldur.name`: the module declares
    # `users.users.''${username}`, and attribute *names* may not depend on the
    # option's own merged value — that reference infinitely recurses.
    username = "aldur";
    imageName = "aldur-nixos";
    homeManagerMarker = ".config/fish/config.fish";
    hostName = "nixos-apple-container"; # Default container name
  };

  programs.aldur = {
    lazyvim.enable = true;
    lazyvim.packageNames = [ "lazyvim" ];
    claude-code.enable = true;
    codex.enable = true;
  };

  home-manager.users.aldur = _: {
    programs = {
      git.settings.gpg.ssh.defaultKeyCommand = "sh -c 'echo key::$(ssh-add -L | grep -i sign)'";
      better-nix-search.enable = true;
      llm.enable = true;
    };
  };
}
