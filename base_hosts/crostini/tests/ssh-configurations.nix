# Evaluate both real platform modules, with and without tmpfs /home, then
# ask OpenSSH to parse the rendered configurations as well.
{
  lib,
  runCommand,
  openssh,
  python3,
  configurations,
}:
let
  variants = lib.concatMap (configuration: [
    configuration
    (configuration.extendModules {
      modules = [ { crostini.impermanence.enable = lib.mkForce false; } ];
    })
    (configuration.extendModules {
      modules = [ { networking.enableIPv6 = lib.mkForce true; } ];
    })
  ]) configurations;
  checkedConfig =
    configuration:
    let
      c = configuration.config;
      ssh = c.services.openssh;
    in
    assert ssh.enable;
    assert
      ssh.listenAddresses == (
        [
          {
            addr = "127.0.0.1";
            port = null;
          }
        ]
        ++ lib.optionals c.networking.enableIPv6 [
          {
            addr = "::1";
            port = null;
          }
        ]
      );
    assert ssh.ports == [ 22 ];
    assert !ssh.openFirewall && !ssh.startWhenNeeded;
    assert !(lib.elem 22 c.networking.firewall.allowedTCPPorts);
    assert ssh.settings.AllowUsers == [ "root" ];
    assert ssh.settings.PermitRootLogin == "prohibit-password";
    assert ssh.settings.AuthenticationMethods == "publickey";
    assert !ssh.settings.PasswordAuthentication && !ssh.settings.KbdInteractiveAuthentication;
    assert !ssh.authorizedKeysInHomedir;
    assert ssh.generateHostKeys;
    assert
      ssh.hostKeys == [
        {
          type = "ed25519";
          path = "/persist/ssh/ssh_host_ed25519_key";
        }
      ];
    assert !(c.environment.etc ? "ssh/ssh_host_ed25519_key");
    assert !(c.environment.etc ? "ssh/ssh_host_ed25519_key.pub");
    assert lib.elem "/persist/ssh" c.systemd.services.sshd-keygen.unitConfig.RequiresMountsFor;
    [
      (if c.networking.enableIPv6 then "any" else "inet")
      (toString c.environment.etc."ssh/sshd_config".source)
    ];
in
runCommand "crostini-ssh-configurations"
  {
    nativeBuildInputs = [
      openssh
      python3
    ];
  }
  ''
    python3 - ${lib.escapeShellArgs (lib.concatMap checkedConfig variants)} <<'PY'
    import subprocess
    import sys

    for family, path in zip(sys.argv[1::2], sys.argv[2::2]):
        # -G skips the presence/permissions check on runtime-only host keys.
        output = subprocess.check_output(["sshd", "-G", "-T", "-f", path], text=True)
        settings = {}
        for line in output.splitlines():
            key, _, value = line.partition(" ")
            settings.setdefault(key.lower(), []).append(value)
        expected = ["127.0.0.1:22"] + (["[::1]:22"] if family == "any" else [])
        assert settings["addressfamily"] == [family], output
        assert sorted(settings["listenaddress"]) == expected, output
        assert settings["port"] == ["22"], output
        assert settings["allowusers"] == ["root"], output
        assert settings["permitrootlogin"] in (["prohibit-password"], ["without-password"]), output
        assert settings["authenticationmethods"] == ["publickey"], output
        assert settings["passwordauthentication"] == ["no"], output
        assert settings["kbdinteractiveauthentication"] == ["no"], output
        assert settings["hostkey"] == ["/persist/ssh/ssh_host_ed25519_key"], output
        print(f"PASS {path}: loopback:22, root/publickey, persistent runtime identity")
    PY
    touch $out
  ''
