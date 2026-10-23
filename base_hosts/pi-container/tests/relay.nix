{ pkgs, lib }:
let
  relay = import ../relay.nix { inherit pkgs; };
  sandbox = import ../../../modules/home/agent-sandbox/package.nix { inherit pkgs lib; } {
    enableDbus = false;
    profiles.pi = {
      allowNixDaemon = false;
      allowOutboundNetwork = false;
      extraEnvironmentAllowlist = [ "LLAMA_SOCKET_PATH" ];
    };
  };
in
pkgs.runCommand "pi-model-relay-test" { } ''
  ${pkgs.python3}/bin/python3 ${./relay.py} ${lib.getExe sandbox} ${lib.getExe relay}
  touch "$out"
''
