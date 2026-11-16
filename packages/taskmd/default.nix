{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  testers,
}:

let
  version = "0.8.1";

  src = fetchFromGitHub {
    owner = "driangle";
    repo = "taskmd";
    tag = "v${version}";
    hash = "sha256-KL/4tcdAy7VOKpRnkoYT9dDxPSZzeSiAf+oM01hCSls=";
  };

  # Vendoring cannot run in workspace mode, so drop the workspace and wire the
  # SDK up as a local replacement instead. That keeps this building against the
  # in-tree SDK, exactly like upstream's release does through `go.work` — the
  # `sdk/go` pin in apps/cli/go.mod trails it by a release or two.
  leaveWorkspace = ''
    rm go.work go.work.sum
    go mod edit -replace github.com/driangle/taskmd/sdk/go=../../sdk/go apps/cli/go.mod
  '';

  # Remove the commands that pull in large dependencies: `mcp` (the MCP SDK),
  # `sync` and `import` (the GitHub and Jira clients), and `web` and
  # `web export` (the web server and the SPA). This makes the binary 11 MiB
  # instead of 17 MiB. A command registers itself in a `func init()` of its
  # file. web.go also has helpers for `next`, thus only its `init()` goes. The
  # linker then removes the code that only these commands use.
  removeCommands = ''
    pushd apps/cli/internal/cli
    rm mcp.go sync.go sync_test.go importcmd.go importcmd_test.go \
      web_export.go web_export_test.go web_test.go
    awk '/^func init\(\) \{$/ { skip = 1 } !skip { print } skip && /^\}$/ { skip = 0 }' web.go > web.go.tmp
    mv web.go.tmp web.go
    substituteInPlace suggest_for_test.go \
      --replace-fail 'feedCmd, importCmd, reportCmd, syncCmd,' 'feedCmd, reportCmd,'
    # importcmd_test.go defines chdirTo.
    substituteInPlace templates_cmd_test.go --replace-fail 'chdirTo(t, ' 't.Chdir('
    popd
  '';
in

buildGoModule (finalAttrs: {
  pname = "taskmd";
  inherit version src;

  # The CLI is one module of a Go workspace that also holds the SDK, the web
  # SPA and the docs site. `cmd/taskmd` is its only `package main`, so there is
  # nothing to narrow with `subPackages` — which would also narrow the tests.
  modRoot = "apps/cli";

  # Upstream tests start the watcher in a goroutine, sleep 100 ms, and then
  # change a file. On a loaded CI runner, the watches are not in place yet,
  # and the event is lost. Here, `Start` closes `Ready` when its watches are
  # in place, and the tests wait for it. TestWatcher_DetectsChanges also
  # waits for the change, not for a fixed 200 ms.
  postPatch =
    leaveWorkspace
    + removeCommands
    + ''
      substituteInPlace apps/cli/internal/watcher/watcher.go \
        --replace-fail 'done     chan struct{}' 'done chan struct{}; Ready chan struct{}' \
        --replace-fail 'done:     make(chan struct{}),' 'done: make(chan struct{}), Ready: make(chan struct{}),' \
        --replace-fail 'defer fsw.Close()' 'close(w.Ready); defer fsw.Close()'
      substituteInPlace apps/cli/internal/watcher/watcher_test.go \
        --replace-fail 'time.Sleep(100 * time.Millisecond)' '<-w.Ready' \
        --replace-fail 'os.WriteFile(initial, []byte("# modified"), 0644)' \
          'os.WriteFile(initial, []byte("# modified"), 0644); waitFor(t, &count, 1, "markdown change")'
      substituteInPlace apps/cli/internal/web/worktree_test.go \
        --replace-fail 'time.Sleep(100 * time.Millisecond) // let the watcher register its dirs' '<-w.Ready'
    '';

  # Vendoring needs the workspace gone too, but nothing else from `postPatch`,
  # which that derivation inherits: a change to the removed commands must not
  # rebuild it.
  overrideModAttrs = _: { postPatch = leaveWorkspace; };

  vendorHash = "sha256-jcs2Ik+BY50NVn86c1nQkzsOqGQEUmt6RyNLcluQETw=";

  # `taskmd --version` reads a constant baked into the source, so only the
  # release ldflags upstream also passes are needed here.
  ldflags = [
    "-s"
    "-w"
  ];

  # internal/e2e is entirely behind a `//go:build e2e` tag and drives a binary
  # it builds itself, so there is nothing to run here.
  excludedPackages = [ "internal/e2e" ];

  # TestWatcher_Debounces writes a file 5 times, 10 ms apart, and expects the
  # 100 ms debounce to merge the writes. On a loaded CI runner, the scheduler
  # can hold the test for more than 100 ms between two writes, and the timer
  # fires one more time. The test measures the wall clock, not the code.
  checkFlags = [ "-skip=^TestWatcher_Debounces$" ];

  nativeBuildInputs = [ installShellFiles ];

  postInstall = ''
    installShellCompletion --cmd taskmd \
      --bash <($out/bin/taskmd completion bash) \
      --fish <($out/bin/taskmd completion fish) \
      --zsh <($out/bin/taskmd completion zsh)
  '';

  passthru = {
    # Catches the version constant drifting from the tag this pins.
    tests.version = testers.testVersion {
      package = finalAttrs.finalPackage;
      inherit (finalAttrs) version;
    };

    # Follows GitHub tags: nix-update's default, so no extra flags.
    updatePin = { };

    # Only packaged here because nixpkgs has no taskmd; the nixpkgs-absence
    # check fails once it does, rather than shadowing it forever.
    absentFromNixpkgs = "taskmd";
  };

  meta = {
    description = "Markdown-based task tracker CLI";
    homepage = "https://github.com/driangle/taskmd";
    license = lib.licenses.mit;
    mainProgram = "taskmd";
  };
})
