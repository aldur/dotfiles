# Options used by NixOS, nix-darwin, and standalone Home Manager.
{
  config,
  lib,
  pkgs,
  ...
}@args:
let
  cfg = config.identity;
  inherit (lib) mkEnableOption mkOption types;
  sandboxOptions = import ../home/agent-sandbox/options.nix { inherit lib pkgs; };
in
{
  options.mainUser = mkOption {
    type = types.str;
    default = "aldur";
    description = "The primary interactive account; also the default standalone Home Manager username.";
  };
  options.extraUsers = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = "Additional interactive accounts. The host declares their uid, home, keys and groups.";
  };
  options.interactiveUsers = mkOption {
    type = types.listOf types.str;
    readOnly = true;
    default = [ config.mainUser ] ++ config.extraUsers;
    description = "The primary and additional interactive accounts.";
  };

  options.identity = {
    githubUser = lib.mkOption {
      type = lib.types.str;
      default = "aldur";
      description = ''
        The GitHub account of the primary user. It gives the git identity
        and the default of `identity.authorizedKeys`.
      '';
    };

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = import ../../utils/github-keys.nix { username = cfg.githubUser; };
      defaultText = lib.literalExpression "the keys of https://github.com/<identity.githubUser>.keys";
      description = ''
        SSH login keys. Hosts use this list for their authorized_keys files.
        For another GitHub account, provide the pinned list explicitly with
        utils.github-keys { username = …; sha256 = …; }.
        Home Manager carries the same value; it does not enable SSH login.
      '';
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.githubUser}@users.noreply.github.com";
      description = ''
        The git `user.email` of the primary user. Also the principal of the
        signing keys in the git allowed-signers file.
      '';
    };
  };
  options.programs.aldur = {
    claude-code = {
      enable = mkEnableOption "claude-code";
      sandbox = sandboxOptions "claude-yolo";
      preferLocalInstallation = mkOption {
        type = types.bool;
        default =
          pkgs.stdenv.hostPlatform.isDarwin
          || (config.programs.nix-ld.enable or false)
          || (config.targets.genericLinux.enable or false);
        description = "Prefer a Claude installation in ~/.local/bin over the Nix package.";
      };
      skills = mkOption {
        type = types.listOf types.str;
        default = [
          "docx"
          "frontend-design"
          "pdf"
          "pptx"
          "webapp-testing"
          "xlsx"
        ];
        description = ''
          The skills from the `claude-skills` package to link into
          ~/.claude/skills. Each skill adds its description to every turn,
          so keep only the skills that you use. Other skills in that
          directory are not managed by Nix.
        '';
      };
    };

    codex = {
      enable = mkEnableOption "codex";
      sandbox = sandboxOptions "codex-yolo";
    };

    profile = mkOption {
      type = types.enum [
        "workstation"
        "headless"
        "minimal"
      ];
      default = args.profile or "workstation";
      readOnly = true;
      description = "Home profile. Select it through specialArgs or extraSpecialArgs.";
    };
  };
}
