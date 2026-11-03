{ runCommandLocal }:

runCommandLocal "pi-startup-header" { } ''
  install -Dm444 ${./index.ts} $out/index.ts
''
