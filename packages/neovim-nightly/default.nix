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
    # Master renamed the desktop entry (org.neovim.nvim.desktop); stable's
    # neovim wrapper still substitutes the old name.
    ln -s org.neovim.nvim.desktop $out/share/applications/nvim.desktop
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
  # Master (neovim/neovim#40625) makes --listen error on socket paths past
  # sun_path (104 bytes on macOS) instead of silently truncating. The test
  # runner pins TMPDIR deep inside the build tree (cmake/RunTests.cmake),
  # long enough here to blow that limit and crash every spawned nvim.
  # $XDG_RUNTIME_DIR wins over the TMPDIR fallback for socket placement
  # and the runner leaves it alone; upstream's own macOS CI survives only
  # because its checkout path is a few bytes shorter.
  preCheck = (old.preCheck or "") + ''
    export XDG_RUNTIME_DIR=$NIX_BUILD_TOP/xdg-run
    mkdir -p "$XDG_RUNTIME_DIR"
  '';
})
