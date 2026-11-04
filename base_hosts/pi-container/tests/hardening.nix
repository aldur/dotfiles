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
    status, output = machine.execute("python -u ${./smoke.py} ${image.image} /var/tmp/pi-root ${./proc-isolation.py} ${image.managedPiSettings} 2>&1", timeout=900)
    assert status == 0, f"Pi container smoke test failed (exit {status}):\n{output}"
    machine.log(output)
  '';
}
