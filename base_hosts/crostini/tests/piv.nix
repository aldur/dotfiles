# The YubiKey path of the guest, with a CanoKey in place of the key. QEMU
# emulates the CanoKey, an open CCID token with a PIV applet that answers
# the Yubico version and serial commands. pcscd runs under ../pcscd.nix,
# yubikey-agent under the NixOS module, as in the guest. yubico-piv-tool
# provisions slot 9a the way `yubikey-agent -setup` does. An SSH login through
# the agent signs with the card, and a scripted pinentry answers the PIN.
# The test cannot cover the firmware of a real key.
{ pkgs }:
let
  # The Assuan protocol, reduced to what go-pinentry-minimal sends. Each
  # PIN request leaves a line in the log.
  pinentry = pkgs.writeShellScriptBin "pinentry" ''
    echo "OK Pleased to meet you"
    while IFS= read -r line; do
      case "$line" in
        GETPIN*)
          echo "$line" >> /tmp/pinentry.log
          echo "D 123456"
          echo "OK"
          ;;
        BYE*)
          echo "OK closing connection"
          exit 0
          ;;
        *) echo "OK" ;;
      esac
    done
  '';
  managementKey = "010203040506070801020304050607080102030405060708";
  agentSock = "/run/user/1000/yubikey-agent/yubikey-agent.sock";
in
pkgs.testers.runNixOSTest {
  name = "crostini-piv";

  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [ ../pcscd.nix ];
      services.yubikey-agent.enable = true;
      programs.gnupg.agent.pinentryPackage = pinentry;
      services.openssh.enable = true;
      environment.systemPackages = [
        pkgs.opensc
        pkgs.yubico-piv-tool
      ];

      users.users.tester = {
        isNormalUser = true;
        uid = 1000;
        # The user manager, and with it yubikey-agent, starts at boot.
        linger = true;
      };

      virtualisation.qemu.package = lib.mkForce (pkgs.qemu_test.override { canokeySupport = true; });
      virtualisation.qemu.options = [
        "-device nec-usb-xhci,id=xhci"
        # The device creates its state file when it is missing.
        "-device canokey,bus=xhci.0,file=\${TMPDIR:-/tmp}/canokey-file"
      ];
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("pcscd.socket")
    machine.wait_for_unit("yubikey-agent.service", user="tester")

    def as_tester(command):
        return machine.succeed(f"su - tester -c 'SSH_AUTH_SOCK=${agentSock} {command}'")

    # The card is there, through pcscd.
    readers = machine.succeed("opensc-tool --list-readers")
    assert "Canokey" in readers, readers
    tool = "yubico-piv-tool --reader Canokey"
    version = machine.succeed(f"{tool} -a version")
    assert "version" in version, version

    # Slot 9a as `yubikey-agent -setup` fills it: an EC P-256 key with the
    # PIN asked once per session and no touch, plus a self-signed
    # certificate. The default PIN and management key of a new card.
    machine.succeed(
        f"{tool} -a generate -s 9a -A ECCP256 --pin-policy=once --touch-policy=never"
        f" --key=${managementKey} -o /tmp/9a.pub",
        f"{tool} -a verify-pin -P 123456 -a selfsign-certificate -s 9a"
        f" -S /CN=crostini-piv/ -i /tmp/9a.pub -o /tmp/9a.crt",
        f"{tool} -a import-certificate -s 9a --key=${managementKey} -i /tmp/9a.crt",
    )

    # The agent serves the key of the slot.
    pub = as_tester("ssh-add -L").strip()
    assert pub.startswith("ecdsa-sha2-nistp256 "), pub
    assert "PIV Slot 9a" in pub, pub

    # A login signs with the card. The scripted pinentry answers the PIN.
    machine.succeed(
        "install -d -m 700 -o tester -g users ~tester/.ssh",
        f"echo '{pub}' > ~tester/.ssh/authorized_keys",
        "chown tester:users ~tester/.ssh/authorized_keys",
    )
    who = as_tester("ssh -o StrictHostKeyChecking=no -o BatchMode=yes localhost id -un")
    assert who.strip() == "tester", who
    machine.succeed("grep -q GETPIN /tmp/pinentry.log")

    # The hardened pcscd unit served all of it.
    show = machine.succeed("systemctl show pcscd.service -p User -p DevicePolicy -p RestrictAddressFamilies")
    for want in ["User=pcscd", "DevicePolicy=closed", "RestrictAddressFamilies=AF_NETLINK AF_UNIX"]:
        assert want in show, show

    failed = machine.succeed("systemctl list-units --state=failed --no-legend --plain")
    assert failed.strip() == "", failed
  '';
}
