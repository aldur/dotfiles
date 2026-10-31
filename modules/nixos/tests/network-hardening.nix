{ pkgs }:
let
  guest =
    backend: suffix:
    { ... }:
    {
      imports = [ ../hardening.nix ];
      networking = {
        nftables.enable = backend == "nftables";
        firewall = {
          allowedTCPPorts = [ 8080 ];
          trustedInterfaces = [ "eth1" ];
        };
        interfaces.eth1 = {
          ipv4.addresses = [
            {
              address = "192.168.1.${suffix}";
              prefixLength = 24;
            }
          ];
          ipv6.addresses = [
            {
              address = "fd00:1::${suffix}";
              prefixLength = 64;
            }
          ];
        };
      };
      environment.systemPackages = [ pkgs.python3 ];
      systemd.services.http = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python -m http.server 8080 --bind ::";
      };
      virtualisation.memorySize = 512;
    };
in
pkgs.testers.runNixOSTest {
  name = "network-hardening";
  requiredFeatures.kvm = false;
  globalTimeout = 600;
  nodes = {
    iptables = guest "iptables" "1";
    nftables = guest "nftables" "2";
  };
  testScript = ''
    import json

    def drops(machine):
        if machine is iptables:
            rules = machine.succeed("iptables -t raw -L nixos-tcp-ip-options -nvx")
            return sum(int(line.split()[0]) for line in rules.splitlines() if "DROP" in line)
        rules = json.loads(machine.succeed("nft -j list chain ip tcp-ip-options drop_tcp_ip_options"))
        return sum(
            expr["counter"]["packets"]
            for item in rules["nftables"]
            for expr in item.get("rule", {}).get("expr", [])
            if "counter" in expr
        )

    def check(server, client, suffix):
        server.wait_for_unit("http.service")
        assert server.succeed("sysctl -n net.mptcp.enabled").strip() == "0"
        assert not server.succeed("ss -HlnM").strip()
        before = drops(server)
        client.succeed("python ${./tcp-ip-options.py} 192.168.1." + suffix + " fd00:1::" + suffix)
        assert drops(server) >= before + 32
        server.wait_until_succeeds("journalctl -k -g 'tcp-ip-options:' --no-pager | grep SRC=")

    start_all()
    for server, client, suffix, unit in (
        (iptables, nftables, "1", "firewall"),
        (nftables, iptables, "2", "nftables"),
    ):
        with subtest(server.name + " packet filtering"):
            server.wait_for_unit(unit + ".service")
            client.wait_for_unit("network.target")
            check(server, client, suffix)
        with subtest(server.name + " reload"):
            server.succeed("systemctl reload " + unit)
            server.succeed("systemctl reload " + unit)
            check(server, client, suffix)
        with subtest(server.name + " restart"):
            server.succeed("systemctl restart " + unit)
            check(server, client, suffix)
        with subtest(server.name + " reboot"):
            server.shutdown()
            server.start()
            server.wait_for_unit(unit + ".service")
            check(server, client, suffix)
  '';
}
