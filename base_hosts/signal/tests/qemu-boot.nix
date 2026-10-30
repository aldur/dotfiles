{ pkgs, specialArgs }:
let
  probe = ./probe.sh;
in
pkgs.testers.runNixOSTest {
  name = "signal-qemu-boot";
  enableOCR = true;
  node.specialArgs = specialArgs;
  node.pkgsReadOnly = false;
  nodes.machine = { lib, config, ... }: {
    imports = [
      ../desktop.nix
      "${specialArgs.inputs.self}/base_hosts/appliance/tests/compressed-store.nix"
    ];
    users.users.root.hashedPasswordFile = lib.mkForce null;
    virtualisation = {
      memorySize = 4096;
      cores = 4;
      qemu.options = [ "-vga none -device virtio-gpu-pci" ];
    };
    services.dnsmasq.settings.address = "/probe.test/203.0.113.5";
    environment.systemPackages = [
      pkgs.dnsutils
      pkgs.curl
      pkgs.jq
      pkgs.python3
      pkgs.sqlite
    ];
    environment.etc = {
      "appliance-isolation.sh".source =
        "${specialArgs.inputs.self}/base_hosts/appliance/tests/isolation.sh";
      "appliance-state.sh".source =
        "${specialArgs.inputs.self}/base_hosts/appliance/tests/state.sh";
      "signal-probe.sh".source = probe;
      "signal-keyring-probe.sh".source = ./keyring.sh;
      "signal-sandbox.sh".source = ./sandbox.sh;
      "signal-raw".source = "${config.aldur.appliance.application.signal}/bin/signal-desktop";
    };
  };
  testScript = { nodes, ... }: ''
    user = "${nodes.machine.mainUser}"
    import shlex

    def wait_for_text(text, timeout):
        # OCR can stop indefinitely when it processes the inverted password screen.
        with machine.nested(f"waiting for {text} to appear on screen"):
            retry(lambda _: text in machine.get_screen_text(), timeout)

    def as_user(command):
        return f"runuser -u {user} -- env HOME=/home/{user} XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus WAYLAND_DISPLAY=wayland-0 GDK_BACKEND=wayland sh -c {shlex.quote(command)}"

    def session():
        machine.wait_for_unit("cage-tty1.service")
        machine.wait_for_file("/run/user/1000/wayland-0")
        machine.succeed(f"test $(ps -o user= -p $(systemctl show cage-tty1 -p MainPID --value) | xargs) = {user}")

    def pause_session():
        # Keep Cage alive while testing service stops and rejected starts.
        machine.succeed("kill -STOP $(pgrep -P $(systemctl show cage-tty1 -p MainPID --value))")

    def password_prompt(title, password="test-only-keyring-password"):
        wait_for_prompt(title)
        machine.send_chars(password)
        machine.send_key("ret")

    def wait_for_prompt(title):
        try:
            wait_for_text(title, timeout=60)
        except Exception:
            print(machine.execute("journalctl _UID=1000 --no-pager -n 80")[1])
            machine.screenshot("signal-prompt-failure")
            raise

    def unlock(first_use=False):
        password_prompt("Unlock Signal keyring")
        if first_use:
            password_prompt("Confirm Signal keyring password")

    def signal_ready():
        try:
            machine.wait_until_succeeds(as_user("systemctl --user is-active signal.service"), timeout=45)
            wait_for_text("Signal", timeout=180)
            machine.wait_until_succeeds(f"user={user} bash -e /etc/signal-probe.sh", timeout=180)
        except Exception:
            print(machine.execute("journalctl _UID=1000 --no-pager -n 100")[1])
            print(machine.execute(as_user("systemctl --user status signal --no-pager"))[1])
            print(machine.execute("journalctl -u cage-tty1 --no-pager -n 80")[1])
            machine.screenshot("signal-start-failure")
            raise
        machine.fail("pgrep -x 'Xorg|Xwayland|lightdm|xfce4-session'")
        # The .tables command can ignore errors from an encrypted database.
        machine.fail(f"sqlite3 -readonly /home/{user}/.config/Signal/sql/db.sqlite 'SELECT count(*) FROM sqlite_master;'")

    session()
    # Exercise the actual first-run password prompt, launcher and app.
    machine.succeed(as_user("systemctl --user set-environment ELECTRON_ENABLE_LOGGING=1"))
    for rejection, key in enumerate(("esc", "ret"), start=1):
        wait_for_prompt("Unlock Signal keyring")
        machine.send_key(key)
        machine.wait_until_succeeds(
            "test $(journalctl _UID=1000 --no-pager | grep -c 'A nonempty keyring password is required') "
            f"-eq {rejection}", timeout=30
        )
        machine.fail(f"test -e /home/{user}/.local/share/keyrings/login.keyring")
        machine.fail(as_user("systemctl --user is-active signal"))
    password_prompt("Unlock Signal keyring")
    password_prompt("Confirm Signal keyring password", "wrong-password")
    machine.fail(f"test -e /home/{user}/.local/share/keyrings/login.keyring")
    machine.fail(as_user("systemctl --user is-active signal"))
    unlock(first_use=True)
    signal_ready()
    first_pid = machine.succeed(as_user("systemctl --user show signal -p MainPID --value")).strip()
    machine.send_key("ctrl-q")
    machine.wait_until_succeeds(as_user(f"test $(systemctl --user show signal -p MainPID --value) != {first_pid}"))
    signal_ready()
    pause_session()
    machine.succeed(as_user("systemd-run --user --wait true"))
    machine.succeed(f"user={user} bash -e /etc/signal-sandbox.sh")
    print(machine.succeed(f"user={user} bash -e /etc/appliance-isolation.sh"))
    dependencies = machine.succeed("systemctl list-dependencies --reverse state.mount --plain --no-pager")
    print(dependencies)
    assert "home-" + user + "-.config-Signal.mount" in dependencies
    assert "home-" + user + "-.local-share-keyrings.mount" in dependencies
    # Each probe must reject a bad state under both callers' shell options.
    machine.succeed("systemd-run --unit=sshd sleep infinity")
    for flags in ("-e", "-euo pipefail"):
        machine.fail(f"user={user} bash {flags} /etc/appliance-isolation.sh")
    machine.succeed("systemctl stop sshd")
    for unit in ("serial-getty@.service", "getty@.service", "container-getty@.service"):
        dropin = f"/run/systemd/system/{unit}.d"
        machine.succeed(f"mkdir -p {dropin}")
        machine.succeed("printf '[Service]\\nExecStart=\\nExecStart=/run/current-system/sw/bin/false --autologin test\\n' > " + dropin + "/autologin.conf")
        machine.succeed("systemctl daemon-reload")
        machine.fail(f"user={user} bash -euo pipefail /etc/appliance-isolation.sh")
        machine.succeed(f"rm {dropin}/autologin.conf")
        machine.succeed("systemctl daemon-reload")
    machine.succeed("cp /run/current-system/sw/bin/true /run/wrappers/capability-probe; setcap cap_net_raw+ep /run/wrappers/capability-probe")
    for flags in ("-e", "-euo pipefail"):
        machine.fail(f"user={user} bash {flags} /etc/appliance-isolation.sh")
    machine.succeed("rm /run/wrappers/capability-probe")
    machine.succeed(as_user("bash -euo pipefail /etc/signal-keyring-probe.sh"))
    profile = f"/home/{user}/.config/Signal"
    machine.succeed(f"cp {profile}/config.json /tmp/signal-config.json")
    machine.succeed(f"jq '.key = \"test-plaintext-key\"' /tmp/signal-config.json > {profile}/config.json")
    for flags in ("-e", "-euo pipefail"):
        machine.fail(f"user={user} bash {flags} /etc/signal-probe.sh")
    machine.succeed(f"cat /tmp/signal-config.json > {profile}/config.json; rm /tmp/signal-config.json")
    machine.screenshot("signal-first-start")
    key = machine.succeed(f"jq -r .encryptedKey /home/{user}/.config/Signal/config.json").strip()

    # A live local service is reachable by root, but not by the app account.
    machine.succeed("systemd-run --unit=local-target python3 -m http.server 8765 --bind 0.0.0.0")
    machine.wait_for_open_port(8765)
    machine.succeed("curl --fail http://127.0.0.1:8765/ >/dev/null")
    machine.fail(as_user("curl --max-time 3 http://127.0.0.1:8765/"))
    machine.succeed("ip addr add 10.77.0.1/32 dev lo; ip addr add 93.184.216.34/32 dev lo")
    machine.succeed("curl --fail http://10.77.0.1:8765/ >/dev/null")
    machine.fail(as_user("curl --max-time 3 http://10.77.0.1:8765/"))
    machine.succeed(as_user("curl --fail --max-time 3 http://93.184.216.34:8765/ >/dev/null"))
    machine.succeed("systemd-run --unit=local-target6 python3 -m http.server 8766 --bind ::")
    machine.wait_for_open_port(8766)
    machine.succeed("curl --noproxy '*' --fail 'http://[::1]:8766/' >/dev/null")
    machine.fail(as_user("curl --noproxy '*' --max-time 3 'http://[::1]:8766/'"))
    machine.succeed("ip -6 addr add fd00::1/128 dev lo")
    machine.succeed("curl --noproxy '*' --fail 'http://[fd00::1]:8766/' >/dev/null")
    machine.fail(as_user("curl --noproxy '*' --max-time 3 'http://[fd00::1]:8766/'"))
    machine.fail(as_user("test -r /dev/vda"))


    # Check the real service's mount sandbox, not merely its unit settings.
    pid = machine.succeed(as_user("systemctl --user show signal -p MainPID --value")).strip()
    machine.fail(f"grep -zq '^ELECTRON_ENABLE_LOGGING=' /proc/{pid}/environ")
    machine.succeed(f"grep -q '^NoNewPrivs:[[:space:]]*1$' /proc/{pid}/status")
    machine.fail(f"nsenter -t {pid} -m -- touch /etc/signal-forbidden")
    machine.fail(f"nsenter -t {pid} -m -- touch /home/{user}/signal-forbidden")
    machine.fail(f"nsenter -t {pid} -m -- test -e /home/{user}/.local/share/keyrings/login.keyring")
    machine.succeed(f"nsenter -t {pid} -m -- grep -q 'nameserver 127.0.0.53' /etc/resolv.conf")
    machine.succeed(f"nsenter -t {pid} -U -m --setuid=1000 --setgid=100 -- getent ahostsv4 probe.test | grep 203.0.113.5")
    for transport in ("+tcp", "+notcp"):
        machine.succeed(as_user(f"dig @127.0.0.53 probe.test +short {transport} | grep -x 203.0.113.5"))
    machine.succeed("systemd-run --unit=dns-target ${pkgs.dnsmasq}/bin/dnsmasq --keep-in-foreground --conf-file=/dev/null --no-resolv --bind-interfaces --listen-address=127.0.0.1,10.77.0.1,::1,fd00::1 --address=/probe.test/203.0.113.5")
    machine.wait_until_succeeds("dig @10.77.0.1 probe.test +short | grep -x 203.0.113.5")
    for address in ("127.0.0.1", "10.77.0.1", "::1", "fd00::1"):
        for transport in ("+tcp", "+notcp"):
            query = f"dig @{address} probe.test +time=1 +tries=1 {transport}"
            machine.succeed(query + " | grep 203.0.113.5")
            machine.fail(as_user(query))
    machine.succeed(f"nsenter -t {pid} -m -- touch /home/{user}/.config/Signal/persistence-probe")
    machine.succeed(as_user("systemctl --user stop signal.service"))
    machine.succeed("systemctl stop dnsmasq")
    machine.fail(as_user("systemctl --user start signal.service"))
    machine.succeed("systemctl start dnsmasq")
    machine.succeed("systemctl stop firewall")
    machine.fail(as_user("systemctl --user start signal.service"))
    machine.succeed("systemctl start firewall")
    machine.succeed("kill -CONT $(pgrep -P $(systemctl show cage-tty1 -p MainPID --value))")
    print(machine.succeed(f"user={user} persist='.config/Signal .local/share/keyrings' bash /etc/appliance-state.sh plant"))
    machine.shutdown()
    machine.start()
    session()
    print(machine.succeed(f"user={user} persist='.config/Signal .local/share/keyrings' bash /etc/appliance-state.sh verify"))
    password_prompt("Unlock Signal keyring", "wrong-password")
    try:
        machine.wait_until_succeeds("journalctl _UID=1000 --no-pager | grep 'Incorrect keyring password'", timeout=20)
    except Exception:
        print(machine.execute("journalctl _UID=1000 --no-pager -n 80")[1])
        machine.screenshot("signal-password-failure")
        raise
    machine.fail(as_user("systemctl --user is-active signal"))
    unlock()
    signal_ready()
    pause_session()
    assert key == machine.succeed(f"jq -r .encryptedKey /home/{user}/.config/Signal/config.json").strip()
    machine.succeed(f"test -f /home/{user}/.config/Signal/persistence-probe")
    machine.screenshot("signal-after-restart")

    # Deliberately force Electron's insecure backend, bypassing the launcher.
    # The app-level guard must prevent creating even a fresh plaintext profile.
    machine.succeed(as_user("systemctl --user stop signal.service"))
    machine.succeed(as_user("systemd-run --user --unit=signal-insecure /etc/signal-raw --password-store=basic --user-data-dir=/home/" + user + "/insecure-profile --ozone-platform=wayland --disable-gpu"))
    try:
        machine.wait_until_succeeds("journalctl _UID=1000 --no-pager | grep 'plaintext key storage is forbidden'", timeout=45)
        wait_for_text("Secure keyring required", timeout=45)
        machine.send_key("esc")
        machine.wait_until_fails(as_user("systemctl --user is-active signal-insecure"), timeout=45)
    except Exception:
        print(machine.execute("journalctl _UID=1000 --no-pager -n 100")[1])
        print(machine.get_screen_text())
        machine.screenshot("signal-insecure-failure")
        raise
    machine.succeed(as_user("systemctl --user stop signal-insecure"))
    machine.fail(f"test -f /home/{user}/insecure-profile/sql/db.sqlite")
    machine.succeed(as_user("busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service Lock ao 1 /org/freedesktop/secrets/collection/login"))
    machine.fail(as_user("systemctl --user start signal.service"))
    machine.succeed("journalctl _UID=1000 --no-pager | grep 'Keyring is locked'")
    machine.fail(as_user("signal-desktop --no-sandbox"))

    machine.succeed("mkdir -p /run/systemd/system/firewall.service.d")
    machine.succeed("printf '[Service]\\nExecStartPre=/run/current-system/sw/bin/false\\n' > /run/systemd/system/firewall.service.d/fail.conf")
    machine.succeed("systemctl daemon-reload")
    machine.succeed("systemctl --no-block restart firewall")
    machine.wait_for_shutdown()
  '';
}
