{ nixos }:
let
  inherit (nixos) pkgs config;
  inherit (pkgs) lib;
  python = pkgs.python3.withPackages (ps: [ ps.zstandard ]);
  # Review budget changes explicitly. x86 baseline: 3521 MiB store closure,
  # 1123 MiB OCI archive. ARM has larger binaries, especially Chromium;
  # its conservative limits await the first native CI measurement.
  budgets = {
    x86_64-linux = {
      maxClosureMiB = 3800;
      maxArchiveMiB = 1250;
    };
    aarch64-linux = {
      maxClosureMiB = 4300;
      maxArchiveMiB = 1450;
    };
  };
  policy = pkgs.writeText "container-size-policy.json" (
    builtins.toJSON (
      budgets.${pkgs.stdenv.hostPlatform.system}
      // {
        # Exclusions should not introduce dependencies to build.
        forbiddenPaths = map (p: builtins.unsafeDiscardStringContext (toString p)) [
          pkgs.git
          pkgs.libimagequant
          (lib.getLib pkgs.qpdf)
          (lib.getLib pkgs.libvpx)
        ];
      }
    )
  );
in
pkgs.runCommand "container-image-size"
  {
    __structuredAttrs = true;
    exportReferencesGraph = {
      image = [
        config.system.build.toplevel
        config.system.build.containerEntrypoint
      ];
      nixRuntime = [ config.nix.package ];
    };
  }
  ''
    ${lib.getExe python} ${./guard.py} image \
      --policy ${policy} --graph "$NIX_ATTRS_JSON_FILE" \
      --report "''${outputs[out]}" ${config.system.build.containerImage}
  ''
