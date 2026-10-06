# Exercise the graphical session and browser storage. The only browser-policy
# override is the local test homepage.
{ pkgs, specialArgs }:
pkgs.testers.runNixOSTest {
  name = "browser-qemu-boot";
  node.specialArgs = specialArgs;
  nodes.machine = { lib, ... }: {
    imports = [ ../desktop.nix ];
    # Keep the production root lock; the driver has a separate root console.
    users.users.root.hashedPasswordFile = lib.mkForce null;
    virtualisation = {
      memorySize = 4096;
      cores = 4;
    };
    environment.systemPackages = [ pkgs.xdotool ];
    programs.firefox.policies.Homepage = {
      URL = lib.mkForce "http://localhost/";
      StartPage = "homepage";
    };
    services.nginx = {
      enable = true;
      virtualHosts.localhost.root = pkgs.writeTextDir "index.html" ''
        <!doctype html><meta charset="utf-8">
        <script>
          const visits = Number(localStorage.getItem("visits") || 0) + 1;
          localStorage.setItem("visits", visits);
          document.title = "Browser persistence " + visits;
        </script>
        <p>Persistent browser storage</p>
      '';
    };
  };
  testScript = { nodes, ... }: ''
    import shlex

    user = "${nodes.machine.mainUser}"
    firefox = "${nodes.machine.programs.firefox.finalPackage}/bin/firefox"

    def session():
        machine.wait_for_unit("graphical.target")
        machine.wait_until_succeeds(f"pgrep -u {user} -f xfce4-session")
        environ = machine.succeed(
            f"cat /proc/$(pgrep -u {user} -f xfce4-session | head -n1)/environ | tr '\\0' '\\n'"
        )
        return " ".join(shlex.quote(line) for line in environ.splitlines()
            if line.startswith(("DISPLAY=", "XAUTHORITY=", "DBUS_SESSION_BUS_ADDRESS=", "XDG_RUNTIME_DIR=")))

    def as_user(command):
        return f"runuser -u {user} -- env HOME=/home/{user} {env} sh -c {shlex.quote(command)}"

    env = session()
    machine.wait_until_succeeds(as_user("xdotool search --name 'Browser persistence 1'"))
    machine.succeed("test ! -e /run/wrappers/bin/sudo && test ! -e /run/wrappers/bin/su")
    machine.fail("systemctl is-active sshd.service")
    machine.succeed("systemctl is-active firewall.service systemd-sysctl.service")
    machine.succeed(f"test $(stat -c %a /home/{user}) = 700")
    for directory in ("/tmp", "/var/tmp", "/var/log"):
        machine.succeed(f"test $(findmnt -n -o FSTYPE -T {directory}) = tmpfs")
    machine.succeed("findmnt -n -o OPTIONS / | grep -w nosuid | grep -w nodev")

    # Flush the profile before a complete VM shutdown, as for a backup.
    process = shlex.quote(f"^{firefox}( |$)")
    machine.succeed(as_user(f"pkill -TERM -f {process}"))
    machine.wait_until_fails(f"pgrep -u {user} -f {process}")
    machine.shutdown()
    machine.start()
    env = session()
    machine.wait_until_succeeds(as_user("xdotool search --name 'Browser persistence 2'"))
    machine.screenshot("browser-after-restart")
  '';
}
