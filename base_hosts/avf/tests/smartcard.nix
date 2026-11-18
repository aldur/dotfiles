# The smart card and root paths of the guest. vicc, the card emulator of
# vsmartcard, connects to vpcd as the Android app does. QEMU emulates a
# CanoKey in place of the YubiKey. Its PIV applet signs the root login
# through the OpenSC PKCS#11 module. The test cannot cover NFC and the
# Android app.
{ pkgs }:
let
  managementKey = "010203040506070801020304050607080102030405060708";
  # The PIN prompt of ssh. Each request leaves a line in the log.
  askpass = pkgs.writeShellScript "askpass" ''
    echo "$*" >> /tmp/askpass.log
    echo 123456
  '';
in
pkgs.testers.runNixOSTest {
  name = "avf-smartcard";

  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [
        ../smartcard.nix
        ../../../modules/nixos/ssh-policy.nix
        ../../../modules/nixos/ssh-local-root.nix
      ];
      environment.systemPackages = [
        pkgs.opensc
        pkgs.vsmartcard-vpcd
        pkgs.yubico-piv-tool
      ];
      users.users.aldur.isNormalUser = true;

      virtualisation.qemu.package = lib.mkForce (pkgs.qemu_test.override { canokeySupport = true; });
      virtualisation.qemu.options = [
        "-device nec-usb-xhci,id=xhci"
        # The device creates its state file when it is missing.
        "-device canokey,bus=xhci.0,file=\${TMPDIR:-/tmp}/canokey-file"
      ];
    };

  testScript = ''
    machine.wait_for_unit("pcscd.service")

    with subtest("the driver of vpcd has only its runtime dependencies"):
        driver = machine.succeed("grep -o '/nix/store/[^ ]*libifdvpcd.so' /etc/reader.conf").strip()
        closure = machine.succeed(f"nix-store -qR {driver}")
        for unwanted in ["-gcc-", "-dev", "python3", "vsmartcard"]:
            assert unwanted not in closure, closure

    with subtest("a card connects to vpcd"):
        machine.wait_until_succeeds("ss -ltn | grep -q ':25963 '")
        machine.succeed("systemd-run --unit=vicc vicc --type iso7816 --hostname 127.0.0.1 --port 25963")
        # The columns are: number, card present, features, name.
        machine.wait_until_succeeds("opensc-tool --list-readers | grep -E 'Yes.*Virtual PCD'")
        machine.succeed("systemctl stop vicc")

    with subtest("root logs in with the PIV key"):
        # Slot 9a as `yubikey-agent -setup` fills it, with the default PIN
        # and management key of a new card.
        tool = "yubico-piv-tool --reader Canokey"
        machine.succeed(
            f"{tool} -a generate -s 9a -A ECCP256 --pin-policy=once --touch-policy=never"
            f" --key=${managementKey} -o /tmp/9a.pub",
            f"{tool} -a verify-pin -P 123456 -a selfsign-certificate -s 9a"
            f" -S /CN=avf-smartcard/ -i /tmp/9a.pub -o /tmp/9a.crt",
            f"{tool} -a import-certificate -s 9a --key=${managementKey} -i /tmp/9a.crt",
        )
        pub = machine.succeed("ssh-keygen -D ${pkgs.opensc}/lib/opensc-pkcs11.so").strip()
        assert pub.startswith("ecdsa-sha2-nistp256 "), pub
        machine.succeed(
            "mkdir -p /etc/ssh/authorized_keys.d",
            f"echo '{pub}' > /etc/ssh/authorized_keys.d/root",
        )

        ssh = "SSH_ASKPASS=${askpass} SSH_ASKPASS_REQUIRE=force ssh -o StrictHostKeyChecking=accept-new"
        uid = machine.succeed(f"su - aldur -c '{ssh} root@.host id -u' < /dev/null")
        assert uid.strip() == "0", uid
        machine.succeed("grep -q PIN /tmp/askpass.log")
        machine.fail(f"su - aldur -c '{ssh} aldur@.host true' < /dev/null")

    with subtest("sshd has no network listener"):
        machine.fail("ss -ltn | grep -q ':22 '")
        machine.succeed("test -S /run/ssh-unix-local/socket")
  '';
}
