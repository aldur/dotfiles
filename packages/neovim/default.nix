{ neovim-unwrapped, fetchFromGitHub }:

neovim-unwrapped.overrideAttrs (old: rec {
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
})
