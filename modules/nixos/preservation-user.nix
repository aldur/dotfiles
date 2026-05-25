{
  config,
  lib,
  ...
}:
let
  cfg = config.aldur.preservation-user;
  paths = import ../shared/preservation-paths.nix;

  # The full persist list (concatenated here so the tmpfiles auto-
  # derivation below sees the same entries the preservation module
  # gets).
  persistedDirs =
    paths.base
    ++ lib.optionals cfg.persistLazyvim paths.lazyvim
    ++ lib.optionals cfg.persistLlm paths.llm
    ++ lib.optionals cfg.persistClaudeCode paths.claudeDirectories;

  # Each entry is either "rel/path[/]" or { directory = "rel/path"; ... }.
  toRelPath = entry: lib.removeSuffix "/" (entry.directory or entry);

  # Parents of "a/b/c" → [ "a" "a/b" ]; "a" → [ ]; "" → [ ].
  parentsOf =
    relPath:
    let
      parts = lib.splitString "/" relPath;
      n = lib.length parts;
    in
    lib.genList (i: lib.concatStringsSep "/" (lib.take (i + 1) parts)) (
      lib.max 0 (n - 1)
    );

  intermediateParents = lib.unique (
    lib.concatMap (e: parentsOf (toRelPath e)) persistedDirs
  );
in
{
  options.aldur.preservation-user = {
    enable = lib.mkEnableOption "preservation for the primary user";

    username = lib.mkOption {
      type = lib.types.str;
      default = "aldur";
      description = "User whose home directory is preserved into /persist.";
    };

    persistClaudeCode = lib.mkOption {
      type = lib.types.bool;
      default = config.programs.aldur.claude-code.enable;
      description = "Persist Claude Code state (.claude, .claude.json).";
    };

    persistLazyvim = lib.mkOption {
      type = lib.types.bool;
      default = config.programs.aldur.lazyvim.enable;
      description = "Persist LazyVim state.";
    };

    persistLlm = lib.mkOption {
      type = lib.types.bool;
      # programs.llm is a home-manager option (modules/home/llm.nix), so
      # the source-of-truth lives under home-manager.users.<u>.programs.llm.
      # `or false` keeps eval working on hosts that don't import HM.
      default = config.home-manager.users.${cfg.username}.programs.llm.enable or false;
      description = "Persist datasette llm config (~/.config/io.datasette.llm).";
    };
  };

  config = lib.mkIf cfg.enable {
    preservation.preserveAt."/persist".users.${cfg.username} = {
      commonMountOptions = [ "x-gvfs-hide" ];
      directories =
        paths.base
        ++ lib.optionals cfg.persistLazyvim paths.lazyvim
        ++ lib.optionals cfg.persistLlm paths.llm
        ++ lib.optionals cfg.persistClaudeCode paths.claudeDirectories;
      files = lib.optionals cfg.persistClaudeCode paths.claudeFiles;
    };

    # tmpfiles for the user's home and intermediate parent dirs of each
    # persisted path. Leaves (`.claude`, `.ssh`, etc.) are handled by
    # preservation itself when it sets up the bind-mount target — only
    # the parents need explicit entries here so the chain exists when
    # preservation tries to create the leaves.
    systemd.tmpfiles.settings.preservation =
      let
        defaults = {
          user = cfg.username;
          group = "users";
          mode = "0755";
        };
      in
      {
        "/home/${cfg.username}".d = defaults;
      }
      // lib.listToAttrs (
        map (p: {
          name = "/home/${cfg.username}/${p}";
          value.d = defaults;
        }) intermediateParents
      );

    # user@.service must wait for home-manager activation; otherwise user
    # services start against a half-built home dir.
    systemd.services."user@" = {
      overrideStrategy = "asDropin";
      after = [ "home-manager-${cfg.username}.service" ];
      wants = [ "home-manager-${cfg.username}.service" ];
      serviceConfig.TimeoutStartSec = "90";
    };
  };
}
