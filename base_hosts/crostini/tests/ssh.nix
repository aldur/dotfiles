# Exercise the production SSH module on two isolated VMs. Each has two
# external interfaces, IPv4/IPv6, a persistent disk and an ephemeral home.
{ pkgs }:
let
  inherit (import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs)
    snakeOilEd25519PrivateKey
    snakeOilEd25519PublicKey
    ;
  guest = { ... }: {
    imports = [
      ../ssh.nix
      ../../../modules/nixos/ssh-policy.nix
    ];
    # Deliberately reproduce the defaults that used to widen the boundary.
    services.openssh = {
      openFirewall = true;
      listenAddresses = [ { addr = "0.0.0.0"; } ];
      settings.AllowUsers = [ "aldur" ];
    };
    networking.firewall.enable = false;
    virtualisation.vlans = [
      1
      2
    ];
    virtualisation.emptyDiskImages = [ 128 ];
    virtualisation.fileSystems."/persist" = {
      device = "/dev/vdb";
      fsType = "ext4";
      autoFormat = true;
    };
    virtualisation.fileSystems."/home" = {
      device = "tmpfs";
      fsType = "tmpfs";
    };
    users.users = {
      root.openssh.authorizedKeys.keys = [ snakeOilEd25519PublicKey ];
      # Give aldur the SAME valid key: rejection must be the allowlist.
      aldur = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ snakeOilEd25519PublicKey ];
      };
    };
    # Model an upgrade with a store-backed legacy host key still present.
    # The production module must neither use it nor copy it to /persist.
    environment.etc."ssh/ssh_host_ed25519_key" = {
      source = snakeOilEd25519PrivateKey;
      mode = "0600";
    };
    environment.systemPackages = [ pkgs.python3 ];
  };
in
pkgs.testers.runNixOSTest {
  name = "crostini-ssh";
  nodes = {
    first = { ... }: {
      imports = [ guest ];
      networking.interfaces.eth1.ipv6.addresses = [
        {
          address = "fd00:1::1";
          prefixLength = 64;
        }
      ];
      networking.interfaces.eth2.ipv6.addresses = [
        {
          address = "fd00:2::1";
          prefixLength = 64;
        }
      ];
    };
    second = { ... }: {
      imports = [ guest ];
      networking.interfaces.eth1.ipv6.addresses = [
        {
          address = "fd00:1::2";
          prefixLength = 64;
        }
      ];
      networking.interfaces.eth2.ipv6.addresses = [
        {
          address = "fd00:2::2";
          prefixLength = 64;
        }
      ];
    };
  };

  testScript = ''
    import json
    import shlex

    KEY = "/persist/ssh/ssh_host_ed25519_key"
    SSH = (
        "ssh -F /dev/null -i /root/client-key -o BatchMode=yes "
        "-o IdentitiesOnly=yes -o IdentityAgent=none -o ConnectTimeout=3 "
        "-o StrictHostKeyChecking=yes -o UserKnownHostsFile=/root/known_hosts "
    )


    def fingerprint(machine, key=KEY):
        return machine.succeed(f"ssh-keygen -lf {key}").split()[1]


    def check_boundary(machine, peer):
        # Assert actual listeners, not just the Nix option values.
        listeners = machine.succeed("ss -H -ltn 'sport = :22'").splitlines()
        assert sorted(line.split()[3] for line in listeners) == ["127.0.0.1:22", "[::1]:22"], listeners
        for address in ("127.0.0.1", "::1"):
            assert machine.succeed(SSH + f"root@{address} id -u").strip() == "0"
            status, output = machine.execute(SSH + f"aldur@{address} true 2>&1")
            assert status == 255 and "Permission denied (publickey)" in output, output
        machine.succeed("journalctl -u sshd --grep='User aldur .*not listed in AllowUsers'")

        addresses = json.loads(machine.succeed("ip -j address show"))
        interfaces = {entry["ifname"]: entry for entry in addresses}
        for name in ("eth1", "eth2"):
            external = [address for address in interfaces[name]["addr_info"] if address["scope"] == "global"]
            assert {address["family"] for address in external} == {"inet", "inet6"}, external
            for address in external:
                ip = address["local"]
                # Positive routing control for every address we reject.
                peer.succeed(f"ping -c 1 -W 2 {ip}")
                family = "AF_INET6" if address["family"] == "inet6" else "AF_INET"
                probe = (
                    f"import errno, socket; s = socket.socket(socket.{family}); "
                    f"s.settimeout(3); result = s.connect_ex(('{ip}', 22)); "
                    "assert result == errno.ECONNREFUSED, result"
                )
                # Both the guest itself and a peer see a closed external port.
                for source in (machine, peer):
                    source.succeed("python3 -c " + shlex.quote(probe))


    first.start(allow_reboot=True)
    second.start()
    identities = {}
    for machine in (first, second):
        machine.wait_for_unit("sshd.service")
        machine.wait_for_unit("multi-user.target")
        machine.succeed("install -m 600 ${snakeOilEd25519PrivateKey} /root/client-key")
        # Trust the key through the test console, not an unauthenticated scan.
        machine.succeed(f"awk '{{print \"127.0.0.1,::1 \" $1 \" \" $2}}' {KEY}.pub > /root/known_hosts")
        assert machine.succeed(f"stat -c '%U:%G:%a' {KEY}").strip() == "root:root:600"
        machine.succeed(f"test ! -L {KEY}", "findmnt -M /persist", "findmnt -t tmpfs /home")
        identities[machine.name] = fingerprint(machine)
        assert identities[machine.name] != fingerprint(machine, "/etc/ssh/ssh_host_ed25519_key")

    with subtest("each instance generates a distinct host identity"):
        assert identities[first.name] != identities[second.name]

    with subtest("root-only loopback access with the firewall disabled"):
        check_boundary(first, second)
        check_boundary(second, first)

    with subtest("host identity survives keygen/service restarts and reboot"):
        first.succeed("systemctl restart sshd-keygen.service sshd.service")
        assert fingerprint(first) == identities[first.name]
        first.reboot()
        first.wait_for_unit("sshd.service")
        first.wait_for_unit("multi-user.target")
        assert fingerprint(first) == identities[first.name]
        check_boundary(first, second)
  '';
}
