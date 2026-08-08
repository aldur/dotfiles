{
  lib,
  stdenv,
  neovim-unwrapped,
  fetchFromGitHub,
}:

# Neovim master from source atop stable's dependency set, replacing the
# neovim-nightly-overlay input (which dragged neovim-src and flake-parts into
# the lock and every `nix flake update`). If master outgrows one of stable's
# dependencies this stops building — the CI pin bump notices before a human.
neovim-unwrapped.overrideAttrs (old: {
  pname = "neovim-nightly";
  version = "0-unstable-2026-08-05";

  src = fetchFromGitHub {
    owner = "neovim";
    repo = "neovim";
    rev = "2e3785a702e0f107d22cb32c51f121b157b887b8";
    hash = "sha256-7uh4OppIw6bJhsC+53lGSQw+zSzDrXVDuu6J3R2K2aM=";
  };

  # Stable's patches target its release, not master.
  patches = [ ];

  # nvim reports its own v0.13.0-dev, not this nix-update-friendly label;
  # the functional test suite still runs and must pass.
  dontVersionCheck = true;

  postInstall = (old.postInstall or "") + ''
    # Master changed the name of the desktop entry to
    # org.neovim.nvim.desktop. The neovim wrapper of stable nixpkgs uses
    # the old name. Master installs the entry only on platforms that are
    # not Apple (runtime/CMakeLists.txt, "if(NOT APPLE)"). Make the link
    # only when the entry exists.
    if [ -e $out/share/applications/org.neovim.nvim.desktop ]; then
      ln -s org.neovim.nvim.desktop $out/share/applications/nvim.desktop
    fi
  '';

  passthru = old.passthru or { } // {
    updatePin = {
      # overrideAttrs keeps upstream's meta.position, so nix-update has to be
      # told which file actually holds the pin.
      args = "--version=branch --override-filename packages/neovim-nightly/default.nix";
      verify = "nix build .#lazyvim-nightly";
    };
  };
}
// lib.optionalAttrs stdenv.hostPlatform.isDarwin {
  # On master (neovim/neovim#40625), --listen stops with an error when the
  # socket path is longer than sun_path (104 bytes on macOS). Before, the
  # bind made the path shorter without a message. The test runner sets
  # TMPDIR to a deep path in the build tree (cmake/RunTests.cmake). Here
  # that path is too long, and each test nvim stops immediately. For the
  # socket location, $XDG_RUNTIME_DIR has priority over TMPDIR, and the
  # runner does not change it. The macOS CI of neovim passes only because
  # its checkout path is some bytes shorter.
  preCheck = (old.preCheck or "") + ''
    export XDG_RUNTIME_DIR=$NIX_BUILD_TOP/xdg-run
    mkdir -p "$XDG_RUNTIME_DIR"
  '';
})
