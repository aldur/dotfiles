{ pkgs, lib }:
let
  sandbox = import ../package.nix { inherit pkgs lib; } {
    enableDbus = false;
    profiles.hooks = {
      allowNixDaemon = false;
      runtimeAllowlist = [ "activity.sock" ];
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "agent-sandbox-network";
  # TCG also runs this check on builders without /dev/kvm or /dev/net/tun.
  requiredFeatures.kvm = false;
  globalTimeout = 1200;
  nodes.machine = { ... }: {
    networking.firewall.enable = false;
    networking.resolvconf.enable = false;
    services.resolved.enable = false;
    users.users.tester = {
      isNormalUser = true;
      uid = 1000;
    };
    boot.kernelModules = [ "tun" ];
    environment.systemPackages = [
      pkgs.python3
      pkgs.iproute2
      pkgs.dnsmasq
    ];
    virtualisation.memorySize = 1024;
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("${pkgs.python3}/bin/python3 ${./network.py} ${lib.getExe sandbox} ${../network.py}", timeout=600)
  '';
}
