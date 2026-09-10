{ pkgs }:
let
  fakeTart = pkgs.writeShellScriptBin "tart" ''
    exec ${pkgs.python3}/bin/python3 ${./tart.py} "$@"
  '';
  launcher = pkgs.callPackage ../macos-vm.nix {
    tart = fakeTart;
    guestSystem = pkgs.emptyDirectory;
  };
in
pkgs.runCommand "macos-vm-preflight-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.shellcheck
    ];
  }
  ''
    shellcheck --shell=bash ${../bootstrap.sh}
    python3 ${./lifecycle.py} ${launcher}/bin/macos-vm
    touch "$out"
  ''
