{
  pkgs,
  image,
  dotfiles,
}:
let
  python = pkgs.python3.withPackages (ps: [ ps.zstandard ]);
  policy = pkgs.writeText "pi-image-policy.json" (
    builtins.toJSON {
      maxClosureMiB = if pkgs.stdenv.hostPlatform.isAarch64 then 760 else 690;
      maxArchiveMiB = if pkgs.stdenv.hostPlatform.isAarch64 then 220 else 200;
      forbiddenPaths = [ ];
      forbiddenNames = [
        "^(pnpm|npm|nix|home-manager|glibc-locales|man-db|groff|gettext|gcc-wrapper|clang-wrapper)-[0-9]"
        "^(difftastic|claude-code|codex|llm|llama-cpp|chromium|pandoc|texlive|gopls|rust-analyzer|basedpyright|prettierd|nil|nixfmt)-[0-9]"
        "-(doc|man|info)$"
      ];
    }
  );
in
pkgs.runCommand "pi-container-image-test"
  {
    __structuredAttrs = true;
    exportReferencesGraph = {
      image = [ image.closure ];
      nixRuntime = [ ];
    };
    nativeBuildInputs = [
      python
      pkgs.bubblewrap
    ];
  }
  ''
    mkdir -p "''${outputs[out]}"
    python ${dotfiles}/checks/container-image/guard.py image \
      --policy ${policy} --graph "$NIX_ATTRS_JSON_FILE" \
      --report "''${outputs[out]}/size.json" ${image.image}
    python ${./smoke.py} ${image.image} "$TMPDIR/root" ${./proc-isolation.py}
    touch "''${outputs[out]}/passed"
  ''
