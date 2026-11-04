{
  pkgs,
  dotfiles,
  offline ? false,
}:
let
  inherit (pkgs) lib;
  unstable = dotfiles.inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  # Keep the initial package name. This keeps the binary offsets correct when you replace package references.
  trim =
    package: changes:
    pkgs.runCommand package.name
      (
        {
          inherit (package) meta;
        }
        // lib.optionalAttrs (package ? version) { inherit (package) version; }
        // lib.optionalAttrs (package ? shellPath) {
          passthru.shellPath = package.shellPath;
        }
      )
      ''
        cp -a ${package} "$out"
        chmod -R u+w "$out"
        ${changes}
        find "$out" -type f -exec sed -i 's|${package}|'"$out"'|g' {} +
      '';
  python = trim pkgs.python3 ''
    # Keep venv and ensurepip. Remove the development files, IDLE, tests, and bytecode caches.
    rm -rf "$out/include" "$out/share" "$out/lib/pkgconfig"
    rm -rf "$out"/lib/python*/idlelib "$out"/lib/python*/test
    find "$out" -name '*.a' -delete
    find "$out" -name __pycache__ -type d -prune -exec rm -rf {} +
  '';
  fish = trim pkgs.fish ''
    # The propagated build inputs keep man-db and gettext in the closure.
    rm -rf "$out/nix-support" "$out/share/man" "$out/share/locale" "$out/share/pkgconfig"
    find "$out" -type f -exec sed -i 's|${pkgs.python3}|${python}|g' {} +
    find "$out" -type f -exec ${lib.getExe pkgs.removeReferencesTo} -t ${pkgs.fish.doc} {} +
    # NAR files store each hard link in full. Keep one multicall executable.
    for tool in fish_indent fish_key_reader; do
      if ! cmp -s "$out/bin/fish" "$out/bin/$tool"; then
        echo "fish: $tool is no longer the same executable; review the runtime links" >&2
        exit 1
      fi
      ln -sf fish "$out/bin/$tool"
    done
  '';
  perl = trim pkgs.perl ''
    rm -rf "$out/nix-support"
    find "$out/lib" -type f \( -name '*.pod' -o -name '*.h' -o -name '*.a' \) -delete
  '';
  perlEnv = pkgs.perl.withPackages (p: [
    p.IPCRun
    p.TimeDate
    p.TimeDuration
  ]);
  rewrittenPerlEnv = pkgs.replaceDirectDependencies {
    drv = perlEnv;
    replacements = [
      {
        oldDependency = pkgs.perl;
        newDependency = perl;
      }
    ];
  };
  runtimePerlEnv = trim rewrittenPerlEnv ''
    rm -rf "$out/share" "$out/nix-support"
  '';
  moreutils = pkgs.replaceDirectDependencies {
    drv = pkgs.moreutils;
    replacements = [
      {
        oldDependency = perlEnv;
        newDependency = runtimePerlEnv;
      }
    ];
  };
  piRuntime = trim pkgs.pi-coding-agent ''
    # Use rg and fd from the editor to remove the second libc.
    substituteInPlace "$out/bin/pi" \
      --replace-fail '${unstable.ripgrep}' '${pkgs.ripgrep}' \
      --replace-fail '${unstable.fd}' '${pkgs.fd}'
    # Keep the extension source files, types, and assets. Remove the dependency tests and source maps.
    find "$out/lib/node_modules" -type d \( -name test -o -name tests -o -name __tests__ -o -name examples \) -prune -exec rm -rf {} +
    find "$out/lib/node_modules" -type f -name '*.map' -delete
    # The OpenAI SDK uses compiled files, except for this type metadata target.
    sdk="$out/lib/node_modules/pi-monorepo/node_modules/@earendil-works/pi-ai/node_modules/openai"
    find "$sdk/src" -type f ! -path '*/internal/auth/x509-transport-state.cts' -delete
    find "$sdk/src" -depth -type d -empty -delete
  '';
in
{
  inherit python fish moreutils;
  pi = pkgs.pi.override (
    {
      selfUpdates = false;
      pi-coding-agent = piRuntime;
    }
    // lib.optionalAttrs offline { tavily-cli = null; }
  );
}
