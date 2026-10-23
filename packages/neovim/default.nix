{
  lib,
  stdenv,
  neovim-unwrapped,
  fetchFromGitHub,
}:

neovim-unwrapped.overrideAttrs (
  old:
  rec {
    version = "0.12.6";
    src = fetchFromGitHub {
      owner = "neovim";
      repo = "neovim";
      tag = "v${version}";
      hash = "sha256-lK1gbJyESMN3C/i8cyPFzzlJDYZHzEXugGhCwPVEbNk=";
    };

    passthru = (old.passthru or { }) // {
      updatePin = {
        args = "--override-filename packages/neovim/default.nix";
        verify = "nix build .#lazyvim .#lazyvim-light";
      };
    };
  }
  // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    # The test runner sets TMPDIR to a path that exceeds the macOS socket
    # path limit. XDG_RUNTIME_DIR takes priority and stays unchanged.
    # Use the same short path as packages/neovim-nightly/default.nix.
    preCheck = (old.preCheck or "") + ''
      export XDG_RUNTIME_DIR=$NIX_BUILD_TOP/xdg-run
      mkdir -p "$XDG_RUNTIME_DIR"
    '';
  }
)
