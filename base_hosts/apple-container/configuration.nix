{ inputs, pkgs, ... }:
{
  imports = [
    ./apple-container.nix
    "${inputs.self}/modules/nixos/pragmatism.nix"
  ];

  users.users.aldur.openssh.authorizedKeys.keys = inputs.self.utils.github-keys;

  # `aldur` gets git via home-manager, but root has none — put it in the system
  # profile so root can drive a flake clone (`nixos-rebuild --flake …`).
  environment.systemPackages = [ pkgs.git ];

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

    # A llama-server on the macOS host is reachable at the gateway of Apple
    # `container`'s default subnet. The bundled pi-llama plugin reads
    # LLAMA_BASE_URL (an OpenAI-style base, /v1 included).
    home.shellAliases = {
      pi = "env LLAMA_BASE_URL=http://192.168.64.1:8080/v1 pi";
      # Same, but jailed on the network side only: nothing reachable except
      # the llama-server hole, while all of $HOME stays writable (the rest of
      # the filesystem is still read-only). Inside the sandbox the server
      # appears at 127.0.0.1 — the relay door — not the gateway.
      faraday-pi = "faraday --allow 192.168.64.1:8080 --writable-home -- env LLAMA_BASE_URL=http://127.0.0.1:8080/v1 pi";
    };
  };
}
