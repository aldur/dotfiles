final: prev:
let
  neovideIcon = prev.fetchurl {
    url = "https://github.com/austinlongmn/neovide/raw/38332a2ca20dd4236044cbf42f244abec1488928/extra/osx/Neovide.app/Contents/Resources/Neovide.icns";
    hash = "sha256-GpujZvTHX0bWuQyEAEWf419zmjtcCZ4dUbsuLWDScfg=";
  };
in
{
  neovide =
    (prev.neovide.override {
      # only used for checks
      neovim = prev.neovim-unwrapped;
    }).overrideAttrs
      (old: {
        postInstall =
          old.postInstall
          + prev.lib.optionalString prev.stdenv.hostPlatform.isDarwin ''
            cp ${neovideIcon} $out/Applications/Neovide.app/Contents/Resources/Neovide.icns
          '';
      });
}
