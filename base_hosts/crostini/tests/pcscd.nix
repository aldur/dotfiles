# Boot a VM with an emulated CCID reader. pcscd, under the unit of
# ../pcscd.nix, must list the reader, and a second reader that arrives at
# runtime. This covers the USB device access and the netlink hotplug path
# of the hardened unit. A YubiKey is a CCID reader of the same class.
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "crostini-pcscd";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../pcscd.nix ];
      services.pcscd.enable = true;
      environment.systemPackages = [ pkgs.opensc ];
      virtualisation.qemu.options = [
        "-device nec-usb-xhci,id=xhci"
        "-device usb-ccid,bus=xhci.0,id=reader0"
      ];
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("pcscd.socket")

    readers = machine.succeed("opensc-tool --list-readers")
    assert readers.count("Gemalto") == 1, readers

    # The restrictions are in the running unit. systemd prints the
    # normalized values.
    show = machine.succeed(
        "systemctl show pcscd.service -p User -p DevicePolicy -p DeviceAllow -p RestrictAddressFamilies -p IPAddressDeny"
    )
    for want in [
        "User=pcscd",
        "DevicePolicy=closed",
        "DeviceAllow=char-usb_device rw",
        "RestrictAddressFamilies=AF_NETLINK AF_UNIX",
    ]:
        assert want in show, show

    # systemd may return the IPv4 and IPv6 deny rules in either order.
    properties = dict(line.split("=", 1) for line in show.splitlines())
    assert set(properties["IPAddressDeny"].split()) == {"0.0.0.0/0", "::/0"}, show

    # Hotplug: the second reader reaches pcscd over netlink.
    machine.send_monitor_command("device_add usb-ccid,bus=xhci.0,id=reader1")
    machine.wait_until_succeeds(
        "opensc-tool --list-readers | grep -c Gemalto | grep -qx 2", timeout=30
    )

    failed = machine.succeed("systemctl list-units --state=failed --no-legend --plain")
    assert failed.strip() == "", failed
  '';
}
