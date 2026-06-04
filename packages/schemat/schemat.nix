{
  makeRustPlatform,
}:
with import <nixpkgs> {
  overlays = [
    (import (fetchTarball "https://github.com/oxalica/rust-overlay/archive/c30ca201c5093540cf792f6982f81ba1aa0f3514.tar.gz"))
  ];
};
let
  rustPlatform = makeRustPlatform {
    cargo = rust-bin.selectLatestNightlyWith (toolchain: toolchain.default);
    rustc = rust-bin.selectLatestNightlyWith (toolchain: toolchain.default);
  };
in
rustPlatform.buildRustPackage rec {
  name = "schemat";
  version = "v0.5.2";
  src = fetchFromGitHub {
    owner = "raviqqe";
    repo = name;
    rev = version;
    hash = "sha256-Ij7JigbXhE2o0Z61uZ3W/pK7zcQyrX+SMpF0iKsVx30=";
  };

  cargoHash = "sha256-oaET2IGU78TUC98HKsiQnbg7R262ugrn8oiLeKC767s=";
}
