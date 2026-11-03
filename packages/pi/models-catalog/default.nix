{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  bun,
}:

let
  version = "0-unstable-2026-11-03";
  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "models.dev";
    rev = "0c1517c823371cc97d46a8bfa7b382c257141b31";
    hash = "sha256-+WrZsh+Dibsruo85AFOKNhRBVwewggPlLDTuBQlhVA0=";
  };
  # Check these against bun.lock during the build, not during evaluation.
  dependencies = {
    remeda = {
      version = "2.33.7";
      hash = "sha512-cXlyjevWx5AcslOUEETG4o8XYi9UkoCXcJmj7XhPFVbla+ITuOBxv6ijBrmbeg+ZhzmDThkNdO+iXKUfrJep1w==";
    };
    zod = {
      version = "3.24.2";
      hash = "sha512-lY7CDW43ECgW9u1TcT3IoXHflywfVqDYze4waEz812jR/bZ8FHDsl7pFQoSZTz5N+2NqRXs8GBwnAwo3ZNxqhQ==";
    };
  };
in
stdenvNoCC.mkDerivation {
  pname = "models-dev-catalog";
  inherit version src;

  nativeBuildInputs = [ bun ];
  buildPhase = ''
    runHook preBuild
    bun -e '
      const lock = Bun.JSON5.parse(await Bun.file("bun.lock").text());
      for (const [name, expected] of Object.entries(JSON.parse(process.argv[1]))) {
        const actual = lock.packages[name];
        if (actual?.[0] !== `''${name}@''${expected.version}` || actual?.[3] !== expected.hash)
          throw new Error(`Update ''${name} to match bun.lock`);
      }
    ' ${lib.escapeShellArg (builtins.toJSON dependencies)}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: dep: ''
      mkdir -p node_modules/${name}
      tar -xzf ${fetchurl {
        url = "https://registry.npmjs.org/${name}/-/${name}-${dep.version}.tgz";
        inherit (dep) hash;
      }} --strip-components=1 -C node_modules/${name}
    '') dependencies)}
    bun -e 'import { generate } from "./packages/core/src/generate.ts"; console.log(JSON.stringify(await generate("./providers")))' > catalog.json
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    bun -e 'const catalog = await Bun.file("catalog.json").json(); if (!catalog["privatemode-ai"]?.models?.["glm-5.3-flash"]?.limit?.context) throw new Error("Missing Privatemode model metadata")'
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm444 catalog.json $out/catalog.json
    runHook postInstall
  '';

  passthru.updatePin = {
    args = "--version=branch";
    verify = ''
      nix run nixpkgs#bun -- packages/pi/models-catalog/update-deps.mjs \
        "$(nix build .#pi.modelsCatalog.src --no-link --print-out-paths)/bun.lock"
      nix build .#pi -L
    '';
  };
}
