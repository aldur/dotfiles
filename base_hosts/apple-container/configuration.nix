{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  fishWithoutDocs = pkgs.callPackage ./fish-without-docs.nix { };
  piWithDefaultUrl =
    url:
    pkgs.writeShellScript "pi-with-default-url" ''
      # Use the default only if LLAMA_BASE_URL is unset or empty.
      export LLAMA_BASE_URL="''${LLAMA_BASE_URL:-${url}}"
      exec pi "$@"
    '';
in
{
  imports = [
    ./apple-container.nix
    "${inputs.self}/modules/nixos/pragmatism.nix"
  ];

  users.users.${config.mainUser}.openssh.authorizedKeys.keys = config.identity.authorizedKeys;

  # The primary user gets git via home-manager, but root has none — put it in the system
  # profile so root can drive a flake clone (`nixos-rebuild --flake …`).
  environment.systemPackages = [ pkgs.gitMinimal-runtime ];

  # Omit package manuals from this image to keep disk footprint small.
  documentation.doc.enable = false;

  programs.fish.package = fishWithoutDocs;
  users.defaultUserShell = lib.mkForce fishWithoutDocs;

  virtualisation.appleContainer = {
    shell = fishWithoutDocs;
    # mainUser is independent of users.users, which this module populates.
    username = config.mainUser;
    imageName = "aldur-nixos";
    homeManagerMarker = ".config/fish/config.fish";
  };

  programs.aldur = {
    claude-code.enable = true;
    codex.enable = true;
  };

  home-manager.users.${config.mainUser} = _: {
    programs = {
      fish.package = fishWithoutDocs;
      aldur.lazyvim.enable = true;
      git.settings.gpg.ssh.defaultKeyCommand = "sh -c 'echo key::$(ssh-add -L | grep -i sign)'";
      better-nix-search.enable = true;
      pi.enable = true;
    };

    # Use the macOS host server by default. Set LLAMA_BASE_URL to override it.
    # Include /v1 in the URL.
    home.shellAliases = {
      pi = "${piWithDefaultUrl "http://192.168.64.1:8080/v1"}";
      # Only the host server is reachable. Inside the sandbox, use its local
      # relay address. A URL override does not change the allowed server.
      faraday-pi = "faraday --allow 192.168.64.1:8080 --writable-home -- ${piWithDefaultUrl "http://127.0.0.1:8080/v1"}";
    };
  };
}
