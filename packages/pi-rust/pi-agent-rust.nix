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
  version = "0.2.0-unstable-2026-08-05";

  src = fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "pi_agent_rust";
    rev = "f4ae1428f108c6342173995fa38f78a37e4b24c2";
    hash = "sha256-f5h+2NvuBMaOeD9pvoqf0XCTi+Wuhh7JPtKrdlswFe0=";
  };

  cargoHash = "sha256-2JFSK3vbeXMQ3rJotHe+wzSm3HXPYV8wJttb68TGQo4=";

  # The affordance the pi wrapper gets from PI_SKIP_VERSION_CHECK: no start-up
  # release probe (api.github.com here) for a binary Nix manages. There is no
  # env toggle — the default lives in code — so flip it there;
  # `checkForUpdates: true` in settings.json still turns it back on.
  postPatch = ''
    substituteInPlace src/config.rs \
      --replace-fail 'self.check_for_updates.unwrap_or(true)' 'self.check_for_updates.unwrap_or(false)'
  '';

  # Thousands of tests (proptest, conformance, live-tool integration) that
  # upstream already gates its releases on; far too slow for a pin bump.
  doCheck = false;

  passthru.updatePin = {
    # Upstream tags rarely (v0.1.9 trails master by months) and develops on
    # the default branch, so track it — same reasoning as pi following
    # nixpkgs-unstable.
    args = "--version=branch";
    verify = "nix build .#pi-rust -L";
  };

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
