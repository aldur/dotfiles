_: {
  systemd.services.pcscd.serviceConfig = {
    # libusb opens the reader under /dev/bus/usb. libudev receives the
    # hotplug events over netlink.
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_NETLINK"
    ];
    IPAddressDeny = "any";
    DevicePolicy = "closed";
    DeviceAllow = [ "char-usb_device rw" ];
  };
}
