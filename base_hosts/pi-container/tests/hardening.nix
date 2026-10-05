{ pkgs, image }:
let
  python = pkgs.python3.withPackages (ps: [ ps.zstandard ]);
in
pkgs.testers.runNixOSTest {
  name = "pi-container-hardening";
  # Permit software emulation on development hosts without /dev/kvm.
  requiredFeatures.kvm = false;
  globalTimeout = 1200;
  nodes.machine = {
    environment.systemPackages = [
      python
      pkgs.runc
    ];
    virtualisation = {
      memorySize = 2048;
      cores = 2;
      diskSize = 4096;
      vlans = [ ];
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("python ${./smoke.py} ${image.image} /var/tmp/pi-root ${./proc-isolation.py} > /dev/console 2>&1", timeout=900)
  '';
}
