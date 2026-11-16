{
  buildGoModule,
  fetchFromGitHub,
  callPackage,
}:

# A terminal browser for a taskmd project: filter and re-sort the task list a
# keypress at a time, next to the detail of whatever is selected.
#
# taskmd itself has no TUI. Upstream built one on Bubble Tea and deleted it
# again in v0.3.0 (`tasks/archive/cli/074-remove-tui-feature.md`) as redundant
# with the CLI and the web dashboard, so this is a separate program rather than
# a patch back into it. It reads the markdown files directly — `taskmd list
# --format json` and `taskmd snapshot` both drop `phase` and `owner`, which are
# filter axes there. The `taskmd` binary has the common taskmd commands, on the
# taskmd Go SDK.
buildGoModule (finalAttrs: {
  pname = "taskmd-ui";
  # Nothing is tagged upstream and development happens on the branch, so the
  # version is the commit's date — the shape `nix-update --version=branch`
  # writes, and what the bump below keeps refreshing.
  version = "0.1.0-unstable-2026-11-16";

  src = fetchFromGitHub {
    owner = "aldur";
    repo = "taskmd-ui";
    rev = "fdb1a00b9729442bb52dd8b93bfe3ba491aaa7d0";
    hash = "sha256-xOWGpgSm2yG5YkZq+KmPcLKjMQNPDO2ESoxK8w0sxOg=";
  };

  vendorHash = "sha256-n3HPmLmOev4pMFegQ1oMFKc25J9Q9QrTB4VRa10qOrk=";

  ldflags = [
    "-s"
    "-w"
  ];

  passthru = {
    tests.smoke = callPackage ./test.nix { taskmd-ui = finalAttrs.finalPackage; };

    updatePin = {
      # Tracks the default branch; nothing is tagged upstream.
      args = "--version=branch";
      verify = "nix build .#taskmd-ui";
    };
  };

  meta = {
    description = "Terminal browser for taskmd projects";
    homepage = "https://github.com/aldur/taskmd-ui";
    mainProgram = "taskmd-ui";
  };
})
