{
  pkgs,
  image,
  dotfiles,
}:
let
  python = pkgs.python3.withPackages (ps: [ ps.zstandard ]);
  policy = pkgs.writeText "pi-image-policy.json" (
    builtins.toJSON {
      maxClosureMiB =
        if image.offline then
          (if pkgs.stdenv.hostPlatform.isAarch64 then 830 else 780)
        else
          (if pkgs.stdenv.hostPlatform.isAarch64 then 1030 else 990);
      maxArchiveMiB =
        if image.offline then
          (if pkgs.stdenv.hostPlatform.isAarch64 then 240 else 220)
        else
          (if pkgs.stdenv.hostPlatform.isAarch64 then 300 else 280);
      forbiddenPaths = [ ];
      forbiddenNames = [
        "^(pnpm|npm|nix|home-manager|glibc-locales|man-db|groff|gettext|gcc-wrapper|clang-wrapper)-[0-9]"
        "^(difftastic|claude-code|codex|llm|llama-cpp|chromium|pandoc|texlive|gopls|rust-analyzer|basedpyright|prettierd|nil|nixfmt)-[0-9]"
        "-(doc|man|info)$"
      ]
      ++ pkgs.lib.optional image.offline "^tavily-(cli|python|skills)-"
      ++ pkgs.lib.optional (!image.offline) "^pi-model-relay$";
    }
  );
  size =
    pkgs.runCommand "pi-container-${image.variant}-size-test"
      {
        __structuredAttrs = true;
        exportReferencesGraph = {
          image = [ image.closure ];
          nixRuntime = [ ];
        };
        nativeBuildInputs = [ python ];
      }
      ''
        mkdir -p "''${outputs[out]}"
        python ${dotfiles}/checks/container-image/guard.py image \
          --policy ${policy} --graph "$NIX_ATTRS_JSON_FILE" \
          --report "''${outputs[out]}/size.json" ${image.image}
      '';
in
{
  inherit size;
  image =
    pkgs.runCommand "pi-container-${image.variant}-smoke-test"
      {
        nativeBuildInputs = [
          python
          pkgs.bubblewrap
        ];
      }
      ''
        python -u ${./smoke.py} ${image.image} "$TMPDIR/root" ${./proc-isolation.py} ${image.managedPiSettings} ${image.variant}
        touch "$out"
      '';
}
