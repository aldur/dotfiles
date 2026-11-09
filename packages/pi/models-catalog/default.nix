{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  bun,
  python3,
}:

let
  version = "sdk-v0.0.5-unstable-2026-11-09";
  src =
    (fetchFromGitHub {
      name = "models-dev-source-${version}";
      owner = "anomalyco";
      repo = "models.dev";
      rev = "74318f789f2775c15967a73fe765752cc0d6e58e";
      hash = "sha256-sJjO4+Lm7xuk/Rg+h8XdvLcEfnQtu3S5ruARqEXh9wY=";
      nativeBuildInputs = [ python3 ];
    }).overrideAttrs
      {
        # Encode model paths before extraction. macOS can merge Qwen and qwen.
        postFetch = ''
          python ${./unpack.py} "$downloadedFile" "$out"
        '';
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
  postPatch = ''
    substituteInPlace packages/core/src/generate.ts \
      --replace-fail 'path.relative(directory, modelPath).split(path.sep).join("/").slice(0, -5)' \
        'Buffer.from(path.basename(modelPath, ".toml"), "hex").toString("utf8")' \
      --replace-fail 'path.relative(modelsPath, modelPath).split(path.sep).join("/").slice(0, -5)' \
        'Buffer.from(path.basename(modelPath, ".toml"), "hex").toString("utf8")'
  '';
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
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: dep: ''
        mkdir -p node_modules/${name}
        tar -xzf ${
          fetchurl {
            url = "https://registry.npmjs.org/${name}/-/${name}-${dep.version}.tgz";
            inherit (dep) hash;
          }
        } --strip-components=1 -C node_modules/${name}
      '') dependencies
    )}
    bun -e 'import { generate } from "./packages/core/src/generate.ts"; console.log(JSON.stringify(await generate("./providers")))' > catalog.json
    runHook postBuild
  '';
  doCheck = true;
  nativeCheckInputs = [ python3 ];
  checkPhase = ''
    runHook preCheck
    PYTHONPATH=${./.} python ${../tests/models-catalog/test_unpack.py}
    bun ${../tests/models-catalog/check.mjs}
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
