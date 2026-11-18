# The units around the guest agent of the Terminal app. The agent itself
# needs the Terminal app on the host and does not start here: these calls
# are the ones that it makes, as its user and with its PATH.
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "avf-agent";

  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [ ../agent.nix ];
      options.mainUser = lib.mkOption { default = "aldur"; };
      config = {
        users.users = {
          aldur.isNormalUser = true;
          other.isNormalUser = true;
        };
        environment.systemPackages = [ pkgs.socat ];
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    path = machine.succeed("systemctl show -P Environment linux-vm-manager | grep -o 'PATH=[^ ]*'").strip()
    def as_agent(command):
        return f"runuser -u aldur -- env {path} {command}"

    with subtest("the agent is the main user and cannot get more privileges"):
        show = machine.succeed("systemctl show linux-vm-manager -p User -p NoNewPrivileges")
        assert "User=aldur" in show and "NoNewPrivileges=yes" in show, show
        assert "/run/wrappers" not in path, path
        machine.fail(as_agent("sudo -u root id"))
        machine.fail(as_agent("sudo -u droid XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 id"))

    with subtest("tcpstates reports the listening ports to the agent only"):
        machine.succeed(
            "systemd-run --uid=aldur --unit=tcpstates-client -p StandardOutput=file:/tmp/tcpstates.log"
            f" env {path} stdbuf -oL /usr/sbin/tcpstates-libbpf"
        )
        machine.wait_until_succeeds("test -s /tmp/tcpstates.log")
        # The agent finds these columns by name.
        header = machine.succeed("head -1 /tmp/tcpstates.log").split()
        for column in ["LPORT", "RPORT", "COMM", "NEWSTATE"]:
            assert column in header, header
        machine.succeed("systemd-run --unit=listener socat TCP-LISTEN:8080,fork,reuseaddr -")
        machine.wait_until_succeeds("grep -E '8080 .*LISTEN' /tmp/tcpstates.log")
        machine.fail("runuser -u other -- /usr/sbin/tcpstates-libbpf")

    with subtest("the poweroff of the agent powers off the guest"):
        # The RuntimeDirectory of the agent.
        machine.succeed("install -d -o aldur -m 700 /run/linux-vm-manager")
        machine.succeed(as_agent("poweroff"))
        machine.wait_for_shutdown()
  '';
}
