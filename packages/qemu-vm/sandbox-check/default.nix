{
  lib,
  fetchurl,
  runCommand,
  writeShellApplication,
  python3,
  lsof,
  qemu,
  # From qemu-vm.nix: the launcher as a function of what it boots, and the
  # guest architecture.
  mkLauncher,
  targetSystem,
}:

# Boots a live Alpine ISO through the qemu-vm launcher and probes the
# sandbox from both sides: what the guest can reach, what the two host
# processes may do, and which sandbox denials the run leaves in the
# unified log. Only the `# -- Boot --` block differs from the real
# launcher, so it runs on a Mac without a Linux builder.
#
# Not a Nix check: it needs the hypervisor, sandbox-exec, the display
# and the network. `nix run .#qemu-vm-sandbox-check`.

let
  arch =
    {
      aarch64-linux = "aarch64";
      x86_64-linux = "x86_64";
    }
    .${targetSystem};

  # Bump: pick the `alpine-virt` entry of
  # https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/<arch>/latest-releases.yaml
  # for each architecture and copy its version and sha256.
  version = "3.24.1";
  hashes = {
    aarch64 = "sha256-yBaZFS2xHSptu311NI1jL89YEe/0FNfnGHaou21IvAI=";
    x86_64 = "sha256-5zpiQb1fPFwtTTjALMUsN4wEFafIiL0pIGa/NuD0Gjk=";
  };
  iso = fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v${lib.versions.majorMinor version}/releases/${arch}/alpine-virt-${version}-${arch}.iso";
    hash = hashes.${arch};
  };

  firmware = "${qemu}/share/qemu/edk2-${arch}-code.fd";

  # The launcher symlinks and reads a store image at start; the ISO does
  # not use one.
  emptyStoreImage = runCommand "empty-store-image" { } ''
    mkdir -p $out
    head -c 4194304 /dev/zero > $out/store.img
  '';

  launcher = mkLauncher {
    name = "qemu-vm-alpine";
    bootArgs = ''
      # The sandbox check: a live ISO through UEFI, on virtio-scsi.
      -bios ${firmware}
      -drive "file=${iso},format=raw,readonly=on,id=cd,if=none,media=cdrom"
      -device virtio-scsi-pci
      -device "scsi-cd,drive=cd,bootindex=0"
    '';
    bootFiles = [
      firmware
      iso
    ];
    storeImage = "${emptyStoreImage}/store.img";
    # SC2034: a live ISO takes no kernel parameters, so that variable goes unused.
    excludeShellChecks = [ "SC2034" ];
  };

  python = python3.withPackages (ps: [
    ps.pexpect
    # CGWindowListCopyWindowInfo, to see the window of `--gui` without
    # screen-recording permission.
    ps.pyobjc-framework-Quartz
  ]);
in
writeShellApplication {
  name = "qemu-vm-sandbox-check";
  runtimeInputs = [
    python
    lsof
  ];
  text = ''
    exec python3 ${./check.py} --launcher ${launcher}/bin/qemu-vm-alpine "$@"
  '';
  meta = {
    description = "Boot a live guest through the qemu-vm launcher and probe its sandbox";
    platforms = lib.platforms.darwin;
  };
}
