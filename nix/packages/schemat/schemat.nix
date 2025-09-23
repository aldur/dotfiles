{
  makeRustPlatform,
}:
with import <nixpkgs> {
  overlays = [
    (import (fetchTarball "https://github.com/oxalica/rust-overlay/archive/954582a766a50ebef5695a9616c93b5386418c08.tar.gz"))
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
  version = "v0.1.23";
  src = fetchFromGitHub {
    owner = "raviqqe";
    repo = name;
    rev = version;
    hash = "sha256-k5Y+Whb0Z2wlEjZOqcf9ex930M+FBokh0Ewt1l1JBoM=";
  };

  useFetchCargoVendor = true;
  cargoHash = "sha256-niHpdA5HfIn0fWFxlKUTSVR/P+lfHHSVGr54Y8nqxcY=";
}
