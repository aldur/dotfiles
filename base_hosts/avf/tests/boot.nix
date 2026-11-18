# The boot check of the image, as the Terminal app boots it: with the kernel,
# the initramfs and the kernel command line of the app (./ferrochrome.nix),
# and with the devices that the guest uses. The disk is as install.sh leaves
# it in the Debian guest. ./probe.sh stands in for the agent on the cidata
# disk. The check boots two times: the first boot moves the Debian files to
# /old-root, the second boot starts the generation through /sbin/init.
#
# The only change to the command line of the app sends the journal to the
# serial console, where the check reads the PROBE lines.
{
  lib,
  callPackage,
  runCommand,
  e2fsprogs,
  gnutar,
  jq,
  libarchive,
  qemu_test,
  util-linux,
  xorriso,
  configuration,
}:
let
  ferrochrome = callPackage ./ferrochrome.nix { };
  tarball = "${configuration.config.system.build.avfImage}/tarball/nixos-terminal.tar.gz";

  cidata = runCommand "avf-test-cidata.iso" { nativeBuildInputs = [ xorriso ]; } ''
    mkdir -p iso/root_files/usr/bin iso/root_files/usr/lib64
    install -m 755 ${./probe.sh} iso/root_files/usr/bin/linux_vm_manager
    touch iso/root_files/usr/lib64/probe-marker
    xorriso -as mkisofs -quiet -R -V cidata -o $out iso
  '';
in
runCommand "avf-boot"
  {
    nativeBuildInputs = [
      e2fsprogs
      gnutar
      jq
      qemu_test
      util-linux
    ];
    requiredSystemFeatures = [ "kvm" ];
  }
  ''
    config=${ferrochrome}/vm_config.json
    offset=$((1024 * 1024))
    root="disk.img?offset=$offset"

    # The disk of the app: one GPT partition, /dev/vda1.
    truncate -s 8G disk.img
    printf 'label: gpt\nstart=2048, type=L, uuid=%s, name=ROOT\n' \
      "$(jq -r '.disks[0].partitions[0].guid' $config)" | sfdisk -q disk.img
    LD_LIBRARY_PATH=${lib.getLib libarchive}/lib \
      mke2fs -q -t ext4 -L ROOT -E offset=$offset -d ${tarball} disk.img 8190M

    # The Debian root, with the mount points of the kernel and stage 2, and
    # the init link that install.sh makes.
    init=$(tar -tvzf ${tarball} nixos-lustrate-init | sed 's/.* -> //')
    echo 13.1 > debian_version
    debugfs -w -f - "$root" > /dev/null <<EOF
    mkdir /dev
    mkdir /proc
    mkdir /run
    mkdir /sys
    mkdir /tmp
    mkdir /etc
    write debian_version /etc/debian_version
    mkdir /home
    mkdir /home/droid
    mkdir /usr
    mkdir /usr/sbin
    symlink /usr/sbin/init $init
    symlink /sbin usr/sbin
    EOF

    boot() {
      timeout 600 qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 4 \
        -m "$(jq -r .memory_mib $config)" -no-reboot -display none -vga none \
        -kernel ${ferrochrome}/vmlinuz -initrd ${ferrochrome}/initrd.img \
        -append "$(jq -r .params $config) systemd.journald.forward_to_console=1" \
        -drive file=disk.img,if=virtio,format=raw \
        -drive file=${cidata},if=virtio,format=raw,readonly=on \
        -device virtio-gpu-pci -device virtio-keyboard-pci -device virtio-tablet-pci \
        -audiodev none,id=sound -device virtio-sound-pci,audiodev=sound \
        -nic user,model=virtio-net-pci \
        -serial file:"$1.log" || echo "QEMU exited with status $?" >> "$1.log"
      # The serial console ends lines with CR LF.
      grep -a 'PROBE ' "$1.log" | tr -d '\r' | sed 's/.*PROBE /PROBE /' > "$1.probe" || true
    }

    verdict=pass
    fail() {
      verdict=fail
      echo "FAIL: $*"
    }
    # The probe powers off the guest. Each boot must report every check.
    report() {
      if ! grep -qx 'PROBE done failures=0' "$1.probe"; then
        fail "the probes of the $1 boot"
        echo "== $1 boot: last lines of the serial console"
        tail -n 80 "$1.log"
      fi
      echo "== $1 boot: probes"
      cat "$1.probe"
      # Stage 2 and the activation write errors only to the console.
      if grep -a -e '/dev/fd/' -e "Activation script snippet '.*' failed" "$1.log"; then
        fail "errors in stage 2 of the $1 boot"
      fi
    }

    boot first
    report first
    grep -aq 'Moving the Debian root to /old-root' first.log ||
      fail "the first boot did not start the lustrate init"
    boot second
    report second
    ! grep -aq 'Moving the Debian root' second.log ||
      fail "the second boot started the lustrate init again"

    # The verdict comes last, after the logs.
    echo "VERDICT $verdict"
    [ $verdict = pass ]
    mkdir $out
    cp first.probe second.probe $out/
  ''
