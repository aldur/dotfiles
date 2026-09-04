# A boot test for a ChromeOS Baguette image, for any guest that builds one
# (see base_hosts/autofirma). It boots the image in crosvm, like ChromeOS
# does, and runs a probe inside it. flake.nix exports this function as
# `lib.mkBaguetteTest`.
#
# The image has no kernel: Baguette boots the ChromeOS kernel. The test
# boots the image with the kernel and the initrd of the same configuration,
# with `boot.kernel` and `boot.initrd` turned back on. The disk is the image
# CI ships, unchanged.
#
# ChromeOS mounts a `cros-vm-tools` disk with maitred, vshd, garcon, and
# sommelier. Those binaries are not public. The test mounts a disk with that
# label that carries sommelier from nixpkgs, stand-ins for the daemons, the
# probe, and the files the caller passes. So the test covers the guest side
# of the ChromeOS integration, not the host side: the ChromeOS daemons that
# talk to maitred and garcon have no counterpart here.
{ lib }:
{
  # The `nixosSystem` that builds the image. It must import
  # `nixos-crostini.nixosModules.baguette`.
  configuration,
  # Attribute name of the derivation.
  name ? "baguette-boot",
  # The interactive user of the guest.
  user ? configuration.config.mainUser,
  # Files for `/opt/google/cros-containers/probe`, as name-to-path pairs.
  # The probe reads them from `$probe`.
  probeFiles ? { },
  # Environment for `as_user`. The probe runs from a unit, not a login
  # session, so it does not have `environment.sessionVariables`.
  userEnv ? { },
  # Shell lines for the probe. Each `PROBE <text>` line they print reaches
  # the checks below. They run as root, with the tools of the image only.
  # `as_user CMD` runs a command as the interactive user.
  extraProbe ? "",
  # Regular expressions, each matched against one `PROBE` line.
  extraChecks ? [ ],
  # Seconds. The guest powers itself off when the probe ends.
  timeout ? 900,
}:
let
  # The guest and the host of the test have the same system, so the
  # packages of the configuration also build the test itself.
  pkgs = configuration.pkgs;

  # The image, and the probe unit that the initrd drops into it.
  shipped = configuration.config.system.build;

  # After the root mount, the initrd drops the probe units into the image.
  # systemd also reads /usr/lib/systemd/system on NixOS. The probe script
  # itself comes from the tools disk. `$1` is the mounted root.
  #
  # A timer starts the probe. A service wanted by multi-user.target could
  # not wait for that target: a cycle. The timer is outside the boot
  # transaction, so the probe runs after every unit of the boot has ended,
  # and sees which ones failed.
  injectProbe = ''
    units=$1/usr/lib/systemd/system
    mkdir -p $units/timers.target.wants
    cat > $units/baguette-probe.timer <<'EOF'
    [Unit]
    Description=Start the Baguette boot probe after the boot

    [Timer]
    OnBootSec=1s
    EOF
    cat > $units/baguette-probe.service <<'EOF'
    [Unit]
    Description=Baguette boot probe
    Requires=opt-google-cros\x2dcontainers.mount
    After=opt-google-cros\x2dcontainers.mount multi-user.target
    SuccessAction=poweroff-force
    FailureAction=poweroff-force

    [Service]
    Type=oneshot
    ExecStart=/opt/google/cros-containers/probe/probe.sh
    # The second serial port of the test. The console of ttyS0 carries
    # the boot messages.
    TTYPath=/dev/ttyS1
    StandardOutput=tty
    StandardError=tty
    EOF
    ln -sf ../baguette-probe.timer $units/timers.target.wants/
  '';

  bootVariant = configuration.extendModules {
    modules = [
      (
        { lib, ... }:
        {
          boot.kernel.enable = lib.mkForce true;
          boot.initrd.enable = lib.mkForce true;
          # The scripted initrd: it hands over to the `init=` of the kernel
          # command line, which points into the image. The systemd initrd
          # wants a `prepare-root` there instead, which an image without
          # an initrd does not have.
          boot.initrd.systemd.enable = lib.mkForce false;
          # The image loads no modules of its own: the ChromeOS kernel has
          # them built in. The initrd loads the ones the guest needs from
          # the NixOS kernel: virtio-gpu for the GBM device of sommelier,
          # fuse for envfs.
          boot.initrd.kernelModules = [
            "virtio_gpu"
            "fuse"
          ];
          boot.initrd.postMountCommands = ''
            set -- $targetRoot
            ${injectProbe}
          '';
        }
        # preservation asserts a systemd initrd. This variant only lends
        # its kernel and initrd; the image keeps its own preservation. The
        # shipped configuration tells whether the option exists at all.
        // lib.optionalAttrs (configuration.config ? preservation) { preservation.enable = lib.mkForce false; }
      )
    ];
  };

  # nixpkgs marks sommelier broken: its test suite fails. The program
  # builds, and the image has all its libraries at the same store paths.
  sommelier = pkgs.sommelier.overrideAttrs (old: {
    doCheck = false;
    buildInputs = old.buildInputs ++ [ pkgs.gtest ];
    meta = old.meta // {
      broken = false;
    };
  });

  # The probe runs as root in the guest. It has what the image has, and no
  # more. The shebang is the /bin/sh of NixOS.
  probe = pkgs.writeShellScript "probe.sh" ''
    export PATH=/run/current-system/sw/bin:/run/wrappers/bin
    probe=/opt/google/cros-containers/probe
    user=${user}
    # The output goes to a serial port with a file behind it. A program
    # that sets terminal modes can stop the port for good, so no flow
    # control, and no program output on the port.
    stty -ixon -ixoff -crtscts 2>/dev/null
    as_user() {
      runuser -u $user -- env HOME=/home/$user XDG_RUNTIME_DIR=/run/user/1000 \
        ${lib.escapeShellArgs (lib.mapAttrsToList (k: v: "${k}=${toString v}") userEnv)} "$@"
    }

    failed=$(systemctl list-units --state=failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')
    echo "PROBE failed [$failed]"
    for unit in $failed; do
      journalctl -u $unit --no-pager -o cat | tail -n 10
    done
    echo "PROBE user $(id $user)"
    echo "PROBE home $(findmnt -n -o FSTYPE /home) $(stat -c '%U %a' /home/$user)"
    echo "PROBE root $(findmnt -n -b -o FSTYPE,SIZE /)"
    echo "PROBE init $(readlink /sbin/init)"
    echo "PROBE usermod $(readlink /usr/sbin/usermod)"

    # The windows of the guest go through sommelier. Its units come from
    # the image; the binary and its GBM backend come from the tools disk.
    # On ChromeOS, maitred opens the user session and grants the render
    # node.
    chmod 0666 /dev/dri/renderD128 2>/dev/null
    loginctl enable-linger $user
    for _ in $(seq 30); do
      as_user systemctl --user is-active --quiet sommelier@0.service 2>/dev/null && break
      sleep 1
    done
    echo "PROBE sommelier $(as_user systemctl --user is-active sommelier@0.service 2>&1)" \
      "$(test -S /run/user/1000/wayland-0 && echo wayland-0 || echo no-socket)"
    as_user systemctl --user status sommelier@0.service --no-pager 2>&1 | tail -n 5

    ${extraProbe}

    echo "PROBE DONE"
  '';

  # The tools of ChromeOS bring their own libraries and dynamic linker.
  # sommelier from nixpkgs finds most of its libraries in the store of the
  # image, at the same paths. The tools disk carries the rest, mainly the
  # GBM backend of mesa, which the image does not ship.
  toolsClosure = pkgs.closureInfo {
    rootPaths = [
      sommelier
      pkgs.mesa
    ];
  };
  imageClosure = pkgs.closureInfo { rootPaths = [ shipped.toplevel ]; };

  # btrfs: the initrd loads it for the root. The image has no modules for
  # the kernel of the test, so no other filesystem mounts in stage 2.
  toolsDisk = pkgs.runCommand "cros-vm-tools.img" { nativeBuildInputs = [ pkgs.btrfs-progs ]; } ''
    mkdir -p root/bin root/lib root/probe

    # Stand-ins for the ChromeOS daemons. Without them, the units of the
    # image fail and restart in a loop, and that flood stalls the serial
    # ports of the test.
    for daemon in vshd maitred garcon port_listener; do
      printf '#!/bin/sh\nexec /run/current-system/sw/bin/sleep infinity\n' > root/bin/$daemon
    done
    printf '#!/bin/sh\nexit 0\n' > root/bin/guest_service_failure_notifier

    # The store paths of the tools that the image lacks. The dynamic linker
    # searches LD_LIBRARY_PATH before the RUNPATH of nixpkgs, so the copies
    # win where the store path is absent.
    libs=
    for path in $(comm -13 <(sort ${imageClosure}/store-paths) <(sort ${toolsClosure}/store-paths)); do
      [ -d $path/lib ] || continue
      cp -r $path/lib root/lib/$(basename $path)
      libs=$libs:/opt/google/cros-containers/lib/$(basename $path)
    done
    mesa=root/lib/$(basename ${pkgs.mesa})

    # The sommelier units of the image call this path. The channel to the
    # host is a virtio-gpu context, not the virtio-wl device of ChromeOS.
    cp ${sommelier}/bin/sommelier root/bin/sommelier-bin
    cat > root/bin/sommelier <<EOF
    #!/bin/sh
    export LD_LIBRARY_PATH=''${libs#:}
    export GBM_BACKENDS_PATH=/opt/google/cros-containers/''${mesa#root/}/gbm
    export LIBGL_DRIVERS_PATH=/opt/google/cros-containers/''${mesa#root/}/dri
    exec /opt/google/cros-containers/bin/sommelier-bin --virtgpu-channel "\$@"
    EOF

    chmod 0755 root/bin/*
    install -m 0755 ${probe} root/probe/probe.sh
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (target: source: "install -m 0444 ${source} root/probe/${target}") probeFiles
    )}

    truncate -s 2G $out
    mkfs.btrfs -q -L cros-vm-tools -r root --shrink $out
  '';

  checks = [
    # The probe runs to its end. Each line below comes from a step of it.
    "DONE"
    # Only the units of the image count. The stand-ins do not fail.
    "failed \\[ *\\]"
    # `vmc start` maps the ChromeOS user onto this UID.
    "user uid=1000(${user})"
    "home tmpfs ${user} 700"
    # The Baguette module links both. The init link is the stage-2 script:
    # `init`, or `prepare-root` with the systemd initrd.
    "init /nix/store/.*/\\(init\\|prepare-root\\)"
    "usermod /nix/store/.*/usermod"
    "sommelier active wayland-0"
  ]
  ++ extraChecks;
in
pkgs.runCommand name
  {
    nativeBuildInputs = [
      pkgs.crosvm
      pkgs.coreutils
    ];
    requiredSystemFeatures = [ "kvm" ];
  }
  ''
    # A disk 2 GiB larger than the image, to also cover the resize at boot.
    cp --sparse=always ${shipped.btrfsImage}/baguette_rootfs.img root.img
    cp ${toolsDisk} tools.img
    chmod u+w root.img tools.img
    image_size=$(stat -c %s root.img)
    truncate -s $((image_size + 2 * 1024 * 1024 * 1024)) root.img

    # The logs go to files. Their lines end in CR and carry colors. Print
    # them clean at the end, also on failure.
    touch console.log probe.log
    show_logs() {
      for f in console.log probe.log; do
        echo "===== $f"
        sed 's/\r$//; s/\x1b\[[0-9;?]*[a-zA-Z]//g' $f
        echo "===== end of $f"
      done
    }
    trap show_logs EXIT

    # ttyS0 is the console, ttyS1 the probe output. No getty on ttyS0: it
    # would take the console away. The GPU gives the guest a render node,
    # which sommelier needs.
    timeout ${toString timeout} crosvm run --disable-sandbox --cpus 2 --mem 3072 \
      --serial type=file,path=console.log,hardware=serial,num=1,console=true \
      --serial type=file,path=probe.log,hardware=serial,num=2 \
      --gpu backend=virglrenderer,context-types=cross-domain \
      --initrd ${bootVariant.config.system.build.initialRamdisk}/initrd \
      --params "init=${shipped.toplevel}/init console=ttyS0 loglevel=4 systemd.getty_auto=no" \
      --block path=tools.img --block path=root.img \
      ${bootVariant.config.system.build.kernel}/${bootVariant.config.system.boot.loader.kernelFile} \
      > crosvm.log 2>&1 || {
      echo "crosvm exit $?"
      tail -n 20 crosvm.log
    }

    mkdir -p $out
    cp console.log probe.log crosvm.log $out/

    # systemd sends a terminal query to the tty before the first line.
    sed 's/\r$//' probe.log | grep -o 'PROBE .*' > probes || true
    cat probes

    status=0
    # Activation grows the filesystem to the size of the disk.
    root_size=$(grep -o '^PROBE root btrfs *[0-9]*' probes | grep -o '[0-9]*$')
    if [ -z "$root_size" ] || [ "$root_size" -le "$image_size" ]; then
      echo "FAIL: root filesystem not grown: $root_size <= $image_size"
      status=1
    fi
    while IFS= read -r want; do
      if ! grep -q "^PROBE $want" probes; then
        echo "FAIL: no PROBE line matches: $want"
        status=1
      fi
    done <<'CHECKS'
    ${lib.concatStringsSep "\n" checks}
    CHECKS
    exit $status
  ''
