# The SSH agent of the guest, end to end: OpenSSH, the bridge, and the agent
# logic of the Android app. The logic runs on a JVM with a software key in
# place of the YubiKey. The test cannot cover the Android part of the app and
# the port forwarding of the Terminal app.
{ pkgs }:
let
  jdk = pkgs.jdk_headless;
  app = pkgs.writeShellScript "app" ''
    exec ${jdk}/bin/java -cp ${pkgs.avf-ssh-agent.core}/share/java/avf-ssh-agent-core.jar \
      io.github.aldur.avfsshagent.core.Main --storepass changeit "$@"
  '';
  keystore = pkgs.writeShellScript "keystore" ''
    for alias in tls ssh; do
      ${jdk}/bin/keytool -genkeypair -keystore "$1" -storetype PKCS12 -storepass changeit \
        -alias $alias -keyalg EC -groupname secp256r1 -dname CN=$alias -validity 3650
    done
  '';
  # A sign request for a session that has no session-bind.
  signWithoutBind = pkgs.writers.writePython3 "sign-without-bind" { } ''
    import base64
    import os
    import socket
    import struct
    import sys


    def string(data):
        return struct.pack(">I", len(data)) + data


    key = base64.b64decode(sys.argv[1])
    method = b"publickey-hostbound-v00@openssh.com"
    data = b"".join([
        string(os.urandom(32)),
        b"\x32",
        string(b"root"),
        string(b"ssh-connection"),
        string(method),
        b"\x01",
        string(b"ecdsa-sha2-nistp256"),
        string(key),
        string(key),
    ])
    request = b"\x0d" + string(key) + string(data) + struct.pack(">I", 0)
    agent = socket.socket(socket.AF_UNIX)
    agent.connect(os.environ["SSH_AUTH_SOCK"])
    agent.sendall(string(request))
    reply = agent.recv(16)
    assert reply == b"\x00\x00\x00\x01\x05", reply
  '';
in
pkgs.testers.runNixOSTest {
  name = "avf-ssh-agent";

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../ssh-agent.nix
        ../../../modules/nixos/ssh-policy.nix
        ../../../modules/nixos/ssh-local-root.nix
      ];
      options.mainUser = lib.mkOption { default = "aldur"; };
      config.users.users.aldur.isNormalUser = true;
    };

  testScript = ''
    import time

    def user(command):
        return f"su - aldur -c '{command}' < /dev/null"

    def start_app(unit, arguments):
        machine.succeed(
            f"systemd-run --unit={unit} -p StandardOutput=append:/tmp/{unit}.log -p StandardError=journal"
            f" ${app} {arguments}"
        )

    def stop_app(unit):
        machine.succeed(f"systemctl stop {unit}; systemctl reset-failed {unit} || true")

    def app_log(unit, pattern):
        machine.wait_until_succeeds(f"grep -E '{pattern}' /tmp/{unit}.log", timeout=30)

    def bridge_log(pattern):
        machine.wait_until_succeeds(
            f"journalctl -u avf-ssh-agent | grep -E '{pattern}'", timeout=30
        )

    # The app sees a refusal only as a closed connection. The bridge logs
    # the reason.
    def refused(keystore, arguments, reason):
        count = f"journalctl -u avf-ssh-agent --no-pager | grep -cE 'refused peer .*{reason}'"
        before = int(machine.succeed(f"{count} || true"))
        start_app("refused", f"--keystore {keystore} --hosts /tmp/none {arguments}")
        machine.wait_until_succeeds(f"test $({count}) -gt {before}", timeout=30)
        stop_app("refused")
        machine.fail("grep '^PAIRED' /tmp/refused.log")

    ssh = "ssh -o StrictHostKeyChecking=accept-new root@.host id -u"

    machine.wait_for_unit("avf-ssh-agent.service")
    machine.wait_until_succeeds("ss -ltn | grep -q '127.0.0.1:25970 '")
    machine.succeed("${keystore} /tmp/app.p12", "${keystore} /tmp/other.p12")
    served = "--keystore /tmp/app.p12 --hosts /tmp/hosts --name-new-hosts this-guest"

    with subtest("the main user and root use the agent"):
        assert machine.succeed(user("echo $SSH_AUTH_SOCK")).strip() == "/run/avf-ssh-agent/agent.sock"
        machine.succeed("ssh -G github.com | grep -qx 'identityagent /run/avf-ssh-agent/agent.sock'")
        machine.succeed("test \"$(stat -c '%U %a' /run/avf-ssh-agent/agent.sock)\" = 'aldur 600'")

    with subtest("the bridge refuses an app that is not paired"):
        line = machine.succeed(user("avf-ssh-agent pair")).strip()
        prefix, version, port, pin, token = line.split(":")
        assert (prefix, version, port) == ("avf-ssh-pair", "v1", "25970"), line
        refused("/tmp/app.p12", f"--port 25970 --pin {pin}", "is not paired")
        assert "paired: no" in machine.succeed(user("avf-ssh-agent status"))

    with subtest("the bridge refuses a wrong token and an expired token"):
        wrong = ":".join([prefix, version, port, pin, "0" * len(token)])
        refused("/tmp/app.p12", f"--pair {wrong}", "pairing refused")
        expired = machine.succeed(user("avf-ssh-agent pair --token-ttl 1s")).strip()
        time.sleep(2)
        refused("/tmp/app.p12", f"--pair {expired}", "pairing refused")
        assert "paired: no" in machine.succeed(user("avf-ssh-agent status"))

    with subtest("the app pairs with the token, one time"):
        line = machine.succeed(user("avf-ssh-agent pair")).strip()
        start_app("app", f"{served} --pair {line}")
        app_log("app", "^PAIRED")
        refused("/tmp/other.p12", f"--pair {line}", "pairing refused")
        status = machine.succeed(user("avf-ssh-agent status"))
        assert "paired: yes" in status and "app: connected" in status, status

    with subtest("the bridge refuses an app with a different pin"):
        refused("/tmp/other.p12", f"--port 25970 --pin {pin}", "is not paired")
        # The paired app stays connected.
        machine.succeed(user("ssh-add -L"))

    with subtest("root logs in through the agent, and the app verifies the destination"):
        public = machine.succeed("${app} --keystore /tmp/app.p12 --print-public-key").strip()
        assert public.startswith("ecdsa-sha2-nistp256 "), public
        assert machine.succeed(user("ssh-add -L")).split()[1] == public.split()[1]
        machine.succeed(
            "mkdir -p /etc/ssh/authorized_keys.d",
            f"echo '{public}' > /etc/ssh/authorized_keys.d/root",
        )
        assert machine.succeed(user(ssh)).strip() == "0"
        app_log("app", "^SIGN userauth user=root host=this-guest fp=SHA256:")
        fingerprint = machine.succeed("ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub").split()[1]
        machine.succeed(f"grep -F 'fp={fingerprint}' /tmp/app.log")
        # root has the same agent.
        assert machine.succeed(f"{ssh} < /dev/null").strip() == "0"

    with subtest("git signs with the agent, and the app shows the namespace"):
        machine.succeed(
            user("ssh-add -L > key.pub && echo text > file && ssh-keygen -Y sign -f key.pub -n git file"),
            user("ssh-keygen -Y check-novalidate -n git -s file.sig < file"),
        )
        app_log("app", "^SIGN sshsig namespace=git")

    with subtest("the app refuses sign data that it cannot verify"):
        refusals = int(machine.succeed("grep -c '^REFUSE' /tmp/app.log || true"))
        # ssh-add -T signs test data that is not an SSH request.
        machine.fail(user("ssh-add -T key.pub"))
        machine.succeed(user(f"${signWithoutBind} {public.split()[1]}"))
        assert int(machine.succeed("grep -c '^REFUSE' /tmp/app.log")) >= refusals + 2

    with subtest("two clients at the same time get their own responses"):
        machine.succeed(user(f"{ssh} > one & {ssh} > two; wait; cat one two | tr -d \"\\n\" | grep -qx 00"))

    with subtest("a dropped connection comes back"):
        machine.succeed("systemctl restart avf-ssh-agent")
        machine.wait_until_succeeds(user("ssh-add -L"), timeout=30)
        assert machine.succeed(user(ssh)).strip() == "0"

    with subtest("with no app, ssh fails in about 15 s"):
        stop_app("app")
        start = time.monotonic()
        machine.fail(user(ssh))
        elapsed = time.monotonic() - start
        assert 10 < elapsed < 25, elapsed
        bridge_log("no app connected")
        assert "not connected" in machine.succeed(user("avf-ssh-agent status"))

    with subtest("the paired app connects again without a token"):
        start_app("app", f"{served} --port 25970 --pin {pin}")
        machine.wait_until_succeeds(user("ssh-add -L"), timeout=30)
        assert machine.succeed(user(ssh)).strip() == "0"
        # The host has a name from the first login.
        machine.succeed("test \"$(wc -l < /tmp/hosts)\" = 1")
  '';
}
