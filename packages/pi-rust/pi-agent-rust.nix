{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

# From-scratch Rust port of the pi coding agent, with the same CLI surface
# where it matters here: `-e` extension flags, package subcommands, ~/.pi
# state. Wrapped by ./pi-rust.nix, which is what ends up on PATH.
rustPlatform.buildRustPackage {
  pname = "pi-agent-rust";
  version = "0.3.0-unstable-2026-08-31";

  src = fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "pi_agent_rust";
    rev = "85b067d336c06b2d6d71d66aea6ccc4b476648ce";
    hash = "sha256-eRmz3vA5kbW2L2WWaCan/42HtQ034+PUUdU7PRsDpF0=";
  };

  cargoHash = "sha256-6nQt5nwC4v2FFecWtMZkv7p/29DAbpWMxRYArjgUow4=";

  # The affordance the pi wrapper gets from PI_SKIP_VERSION_CHECK: no start-up
  # release probe (api.github.com here) for a binary Nix manages. There is no
  # env toggle — the default lives in code — so flip it there;
  # `checkForUpdates: true` in settings.json still turns it back on.
  postPatch = ''
    # Upstream pins a nightly toolchain and passes `-Z threads=4` through
    # `.cargo/config.toml`. The stable rustc from nixpkgs rejects `-Z`
    # options, so remove the file. It only tunes build parallelism, release
    # code layout, and FreeBSD search paths.
    rm -f .cargo/config.toml

    substituteInPlace src/config.rs \
      --replace-fail 'self.check_for_updates.unwrap_or(true)' 'self.check_for_updates.unwrap_or(false)'
  '';

  # The vendored fsqlite crates enable `feature(core_intrinsics)` on x86_64,
  # which needs a nightly rustc. Upstream pins one in rust-toolchain.toml.
  # RUSTC_BOOTSTRAP lets the stable rustc from nixpkgs accept the gate.
  env.RUSTC_BOOTSTRAP = 1;

  # Thousands of tests (proptest, conformance, live-tool integration) that
  # upstream already gates its releases on; far too slow for a pin bump.
  doCheck = false;

  # There is no `verify`. CI finds this package in the wrapper's `passthru`,
  # and the default is `nix build .#pi-rust`.
  passthru.updatePin.args =
    # Upstream tags rarely (v0.1.9 trails master by months) and develops on
    # the default branch, so track it — same reasoning as pi following
    # nixpkgs-unstable.
    "--version=branch";

  meta = {
    description = "Rust port of the pi coding agent";
    homepage = "https://github.com/Dicklesworthstone/pi_agent_rust";
    # MIT plus a rider voiding the grant for OpenAI/Anthropic and anyone
    # acting on their behalf — not `free` by nixpkgs' definition, but marking
    # it so would wall the flake outputs behind allowUnfree for a rider that
    # does not apply here.
    license = lib.licenses.mit // {
      fullName = "MIT License with OpenAI/Anthropic rider";
      url = "https://github.com/Dicklesworthstone/pi_agent_rust/blob/main/LICENSE";
    };
    mainProgram = "pi";
  };
}
