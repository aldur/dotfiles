{
  lib,
  buildGoModule,
  fetchFromGitHub,
  fetchPnpmDeps,
  installShellFiles,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  stdenvNoCC,
  testers,
}:

let
  version = "0.2.7";

  src = fetchFromGitHub {
    owner = "driangle";
    repo = "taskmd";
    tag = "v${version}";
    hash = "sha256-vDZcajc9it8NwLQDzfMEg8YdhSJ3ehYaz5LI4gX3k+k=";
  };

  # Vendoring cannot run in workspace mode, so drop the workspace and wire the
  # SDK up as a local replacement instead. That keeps this building against the
  # in-tree SDK, exactly like upstream's release does through `go.work` — the
  # `sdk/go` pin in apps/cli/go.mod trails it by a release or two.
  leaveWorkspace = ''
    rm go.work go.work.sum
    go mod edit -replace github.com/driangle/taskmd/sdk/go=../../sdk/go apps/cli/go.mod
  '';

  # The SPA `taskmd web` serves. Upstream builds it separately and copies the
  # result into the CLI tree before the release build, so it is a derivation of
  # its own here too.
  web = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "taskmd-web";
    inherit version src;

    # The lockfile lives at the workspace root; only the SPA is installed.
    # pnpm 10 rather than the default: the lockfile is still version 9.
    pnpmWorkspaces = [ "@taskmd/web" ];
    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs)
        pname
        version
        src
        pnpmWorkspaces
        ;
      pnpm = pnpm_10;
      fetcherVersion = 4;
      hash = "sha256-ozv1aGFlus2Wc7OZpoazfatpuULbc3n0Dw3salIkinc=";

      # Reachable as both `taskmd.pnpmDeps` and `taskmd.web.pnpmDeps`, and
      # bumped through taskmd's own pin either way.
      passthru.updatePin.exempt = "lock hash, refreshed when taskmd is bumped";
    };

    nativeBuildInputs = [
      nodejs
      pnpm_10
      pnpmConfigHook
    ];

    buildPhase = ''
      runHook preBuild
      pnpm --filter @taskmd/web build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -r apps/web/dist $out
      runHook postInstall
    '';

    # Shares taskmd's `src`, so bumping taskmd bumps this with it.
    passthru.updatePin.exempt = "same pin as taskmd, bumped through it";
  });
in

buildGoModule (finalAttrs: {
  pname = "taskmd";
  inherit version src;

  # The CLI is one module of a Go workspace that also holds the SDK, the web
  # SPA and the docs site. `cmd/taskmd` is its only `package main`, so there is
  # nothing to narrow with `subPackages` — which would also narrow the tests.
  modRoot = "apps/cli";

  # The `embed_web` build below needs the SPA where `//go:embed` expects it;
  # upstream's release workflow copies it to the same place.
  postPatch = leaveWorkspace + ''
    mkdir -p apps/cli/internal/web/static
    cp -r ${web} apps/cli/internal/web/static/dist
  '';

  # Vendoring needs the workspace gone too, but not the SPA: `postPatch` is
  # inherited by that derivation, and left alone it would block fetching Go
  # modules on a whole pnpm build.
  overrideModAttrs = _: { postPatch = leaveWorkspace; };

  vendorHash = "sha256-Ii3xpwclHvr7azrf48N6lL7k0m84pihb2ZOvzIDn5rA=";

  # Without this the web UI is served from an empty filesystem: `taskmd web
  # start` comes up, but every page is blank.
  tags = [ "embed_web" ];

  # `taskmd --version` reads a constant baked into the source, so only the
  # release ldflags upstream also passes are needed here.
  ldflags = [
    "-s"
    "-w"
  ];

  # internal/e2e is entirely behind a `//go:build e2e` tag and drives a binary
  # it builds itself, so there is nothing to run here.
  excludedPackages = [ "internal/e2e" ];

  # Asserts the failure mode of a build *without* embedded assets, which is
  # exactly what `tags` above turns off.
  checkFlags = [ "-skip=^TestExport_WithoutEmbeddedAssets$" ];

  nativeBuildInputs = [ installShellFiles ];

  postInstall = ''
    installShellCompletion --cmd taskmd \
      --bash <($out/bin/taskmd completion bash) \
      --fish <($out/bin/taskmd completion fish) \
      --zsh <($out/bin/taskmd completion zsh)
  '';

  passthru = {
    inherit web;

    # nix-update only refreshes the pnpm lock hash when it finds `pnpmDeps` on
    # the attribute it is bumping; without this alias a version bump would
    # leave the SPA's dependencies pinned to the old lockfile and fail to
    # build.
    inherit (web) pnpmDeps;

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
