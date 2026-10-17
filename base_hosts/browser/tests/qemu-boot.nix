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
    environment.etc."appliance-isolation.sh".source =
      "${specialArgs.inputs.self}/base_hosts/appliance/tests/isolation.sh";
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
    user = "${nodes.machine.mainUser}"
    firefox = "${nodes.machine.programs.firefox.finalPackage}/bin/firefox"

    ${builtins.readFile "${specialArgs.inputs.self}/base_hosts/appliance/tests/session.py"}

    def wait_for_page(visit):
        try:
            machine.wait_until_succeeds(
                as_user(f"xdotool search --name 'Browser persistence {visit}'"), timeout=180
            )
        except Exception:
            print(machine.execute(as_user("xdotool search --onlyvisible --name '.*' getwindowname %@"))[1])
            machine.screenshot("browser-failure")
            raise

    env = session()
    wait_for_page(1)
    machine.succeed("user=" + user + " bash -e " + "/etc/appliance-isolation.sh")

    # Quit through Firefox so it saves its profile and session before the VM
    # shuts down. A signal is not the user-initiated quit used for backups.
    process = shlex.quote(f"^{firefox}( |$)")
    machine.succeed(as_user(
        "xdotool search --onlyvisible --name 'Browser persistence 1' "
        "windowquit"
    ))
    machine.wait_until_fails(f"pgrep -u {user} -f {process}", timeout=180)
    machine.shutdown()
    machine.start()
    env = session()
    wait_for_page(2)
    machine.screenshot("browser-after-restart")
  '';
}
