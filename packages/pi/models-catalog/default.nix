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
  # Use the generator dependencies and hashes from the pinned upstream lock.
  lockLines = lib.splitString "\n" (builtins.readFile "${src}/bun.lock");
  dependency = name:
    let
      matches = builtins.filter (match: match != null) (map (line:
        builtins.match ''[[:space:]]*"${name}":.*"${name}@([^"]+)".*"(sha512-[^"]+)".*'' line
      ) lockLines);
      locked = builtins.head matches;
    in
    fetchurl {
      url = "https://registry.npmjs.org/${name}/-/${name}-${builtins.elemAt locked 0}.tgz";
      hash = builtins.elemAt locked 1;
    };
in
stdenvNoCC.mkDerivation {
  pname = "models-dev-catalog";
  inherit version src;

  nativeBuildInputs = [ bun ];
  buildPhase = ''
    runHook preBuild
    mkdir -p node_modules/remeda node_modules/zod
    tar -xzf ${dependency "remeda"} --strip-components=1 -C node_modules/remeda
    tar -xzf ${dependency "zod"} --strip-components=1 -C node_modules/zod
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
    verify = "nix build .#pi -L";
  };
}
