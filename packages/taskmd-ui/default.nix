{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  runCommand,
  taskmd,
}:

# A terminal browser for a taskmd project: filter and re-sort the task list a
# keypress at a time, next to the detail of whatever is selected.
#
# taskmd itself has no TUI. Upstream built one on Bubble Tea and deleted it
# again in v0.3.0 (`tasks/archive/cli/074-remove-tui-feature.md`) as redundant
# with the CLI and the web dashboard, so this is a separate program rather than
# a patch back into it. It reads the markdown files directly — `taskmd list
# --format json` and `taskmd snapshot` both drop `phase` and `owner`, which are
# filter axes there — and delegates every write back to the CLI.
buildGoModule (finalAttrs: {
  pname = "taskmd-ui";
  # Nothing is tagged upstream and development happens on the branch, so the
  # version is the commit's date — the shape `nix-update --version=branch`
  # writes, and what the bump below keeps refreshing.
  version = "0.1.0-unstable-2026-08-07";

  src = fetchFromGitHub {
    owner = "aldur";
    repo = "taskmd-ui";
    rev = "d135795ff80adfecd4c47b7f53f17a3c316b2f69";
    hash = "sha256-CMiZxK8wyOmCiSaPelkBpiJdRw+rmw6JrEO82D2mwQc=";
  };

  vendorHash = "sha256-fAb1dbdSRJSFBHN0Fv0OhhfFBzzRX+vDQUV6I8KFTF8=";

  ldflags = [
    "-s"
    "-w"
  ];

  nativeBuildInputs = [ makeWrapper ];

  # Status changes shell out to `taskmd set` rather than rewriting frontmatter
  # there, so the binary is useless without it on PATH. Suffixed rather than
  # prefixed: a project pinning its own taskmd in a dev shell should still get
  # that one, and this is only the fallback that guarantees the keys work.
  postInstall = ''
    wrapProgram $out/bin/taskmd-ui \
      --suffix PATH : ${lib.makeBinPath [ taskmd ]}
  '';

  passthru = {
    # The TUI needs a terminal, so CI cannot drive it; `--version` is the one
    # path that runs without one. It catches the binary failing to start at
    # all, and the wrapper below losing the `taskmd` it depends on — neither of
    # which the compile would notice.
    #
    # Not `testers.testVersion`: the version here is a commit date, while the
    # binary prints the release constant it was cut from, so there is nothing
    # for it to compare.
    tests.smoke =
      runCommand "taskmd-ui-smoke"
        {
          nativeBuildInputs = [ finalAttrs.finalPackage ];
        }
        ''
          taskmd-ui --version | grep -q '^taskmd-ui version '

          # The wrapper's PATH only exists inside the process it wraps, so the
          # dependency is asserted where it is written rather than by calling
          # taskmd here. -a: makeBinaryWrapper emits an executable, not a script.
          grep -qa '${lib.getBin taskmd}/bin' ${finalAttrs.finalPackage}/bin/taskmd-ui

          touch $out
        '';

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
