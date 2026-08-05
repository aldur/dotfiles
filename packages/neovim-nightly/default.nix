{
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
      verify = "nix build .#lazyvim-nightly -L";
    };
  };
})
