{
  pkgs,
  inputs,
  # Configurable defaults
  defaultVmDir ? "$HOME/.local/share/qemu-vm",
  defaultMemory ? 1024 * 16,
  defaultCores ? 8,
  defaultDiskSize ? 64,
  qemuModule ? ../../base_hosts/qemu/qemu.nix,
  ...
}:

let
  inherit (inputs) self nixpkgs;

  # Determine target system based on host
  targetSystem = if pkgs.stdenv.hostPlatform.isAarch64 then "aarch64-linux" else "x86_64-linux";

  baseModules = [
    inputs.self.nixosModules.default
  ];

  # Build the qemu NixOS configuration with proper VM settings
  qemuNixos = nixpkgs.lib.nixosSystem {
    system = targetSystem;
    specialArgs = {
      inputs = inputs // {
        inherit self;
      };
    };
    modules = baseModules ++ [
      qemuModule
      (
        {
          config,
          modulesPath,
          lib,
          options,
          ...
        }:
        {
          virtualisation = {
            diskSize = defaultDiskSize * 1024;
            cores = defaultCores;
            memorySize = defaultMemory;
            writableStoreUseTmpfs = false;
            useBootLoader = false;

            # Build for the host system
            qemu.package = pkgs.qemu;
            host.pkgs = pkgs;
          };
        }
      )
    ];
  };

  targetHostname = qemuNixos.config.networking.hostName;

  # Cross-platform QEMU binary selection (includes machine flags)
  # qemu-common uses pkgs.stdenv.hostPlatform as the *guest* system,
  # so we must pass Linux pkgs (not the host's, which may be darwin).
  guestPkgs = import nixpkgs { system = targetSystem; };
  qemu-common = import "${nixpkgs}/nixos/lib/qemu-common.nix" {
    inherit (nixpkgs) lib;
    pkgs = guestPkgs;
  };
  qemuBinary = qemu-common.qemuBinary pkgs.qemu;
  serialDevice = qemu-common.qemuSerialDevice;
  isLinuxHost = pkgs.stdenv.hostPlatform.isLinux;

  # Paths from the NixOS configuration for direct kernel boot
  inherit (qemuNixos.config.system.build) toplevel;
  inherit (qemuNixos.config.virtualisation.directBoot) initrd;

  # Pre-build the Nix store EROFS image at build time instead of regenerating
  # it on every VM startup. This mirrors the pipeline from NixOS's qemu-vm.nix
  # but runs once during `nix build` rather than on every `qemu-vm` invocation.
  regInfo = pkgs.closureInfo {
    rootPaths = qemuNixos.config.virtualisation.additionalPaths;
  };

  nixStoreImage = pkgs.stdenv.mkDerivation {
    name = "nix-store-image";
    nativeBuildInputs = with pkgs; [
      gnutar
      erofs-utils
    ];
    buildCommand = ''
      mkdir -p $out
      tar --create \
        --absolute-names \
        --verbatim-files-from \
        --transform 'flags=rSh;s|/nix/store/||' \
        --transform 'flags=rSh;s|~nix~case~hack~[[:digit:]]\+||g' \
        --files-from ${
          pkgs.closureInfo {
            rootPaths = [
              qemuNixos.config.system.build.toplevel
              regInfo
            ];
          }
        }/store-paths \
        | mkfs.erofs \
          --quiet \
          --force-uid=0 \
          --force-gid=0 \
          -L nix-store \
          -U eb176051-bd15-49b7-9e6b-462e0b467019 \
          -T 0 \
          --hard-dereference \
          --tar=f \
          $out/store.img
    '';
  };

in
pkgs.writeArgcApplication {
  name = "qemu-vm";
  runtimeInputs = with pkgs; [
    qemu
    coreutils
    e2fsprogs
  ];
  passthru = {
    modules = baseModules;
    storeImage = nixStoreImage;
    nixosConfig = qemuNixos;
  };
  text = ''
    # @describe Spawn a NixOS VM
    # @option -d --dir <DIR> VM disk location [default: ${defaultVmDir}]
    # @option -p --port* <PORT> Forward guest port to host (GUEST_PORT[:HOST_PORT])
    # @option -m --memory <SIZE> Memory size in MB [default: ${toString defaultMemory}]
    # @option --cores <N> Number of CPU cores [default: ${toString defaultCores}]
    # @option --disk-size <SIZE> Disk size in GB [default: ${toString defaultDiskSize}]
    # @option --store-image <PATH> Path to pre-built Nix store image [default: built-in]
    # @flag -v --verbose Verbose output
    # @flag --clean Remove existing VM state
    # @flag --ephemeral Do not write to the VM disk
    # @flag --show-boot Show boot console messages

    declare argc_dir argc_port argc_memory argc_cores argc_disk_size
    declare argc_store_image
    declare argc_verbose argc_clean argc_ephemeral argc_show_boot
    eval "$(argc --argc-eval "$0" "$@")"

    VM_DIR="''${argc_dir:-${defaultVmDir}}"
    MEMORY="''${argc_memory:-${toString defaultMemory}}"
    CORES="''${argc_cores:-${toString defaultCores}}"
    DISK_SIZE="''${argc_disk_size:-${toString defaultDiskSize}}"
    NIX_DISK_IMAGE="$VM_DIR/nixos.qcow2"
    STORE_IMAGE="''${argc_store_image:-${nixStoreImage}/store.img}"

    mkdir -p "$VM_DIR"

    # Handle clean flag
    if [[ "''${argc_clean:-0}" -eq 1 ]]; then
      echo "Cleaning VM state in $VM_DIR..."
      rm -f "$NIX_DISK_IMAGE"
    fi

    # Create disk image if it doesn't exist
    if [[ ! -f "$NIX_DISK_IMAGE" ]]; then
      echo "Creating VM disk: $NIX_DISK_IMAGE (''${DISK_SIZE}G)"
      DISK_SIZE_MB=$((DISK_SIZE * 1024))
      TEMP_RAW=$(mktemp)
      qemu-img create -f raw "$TEMP_RAW" "''${DISK_SIZE_MB}M"
      mkfs.ext4 -L nixos "$TEMP_RAW"
      qemu-img convert -f raw -O qcow2 "$TEMP_RAW" "$NIX_DISK_IMAGE"
      rm "$TEMP_RAW"
    fi

    NIX_DISK_IMAGE=$(readlink -f "$NIX_DISK_IMAGE")

    # Build QEMU network arguments
    QEMU_NET_OPTS=""
    if [[ -n "''${argc_port:-}" ]]; then
      IFS=$'\n' read -r -d "" -a PORTS <<< "''${argc_port:-}" || true
      for i in "''${!PORTS[@]}"; do
        port_spec="''${PORTS[$i]}"
        if [[ "$port_spec" =~ ^([0-9]+):([0-9]+)$ ]]; then
          guest_port="''${BASH_REMATCH[1]}"
          host_port="''${BASH_REMATCH[2]}"
        elif [[ "$port_spec" =~ ^([0-9]+)$ ]]; then
          guest_port="''${BASH_REMATCH[1]}"
          host_port="$guest_port"
        else
          echo "Invalid port specification: $port_spec"
          exit 1
        fi

        if [[ $i -eq 0 ]]; then
          QEMU_NET_OPTS="hostfwd=tcp::$host_port-:$guest_port"
        else
          QEMU_NET_OPTS="$QEMU_NET_OPTS,hostfwd=tcp::$host_port-:$guest_port"
        fi

        if [[ "''${argc_verbose:-0}" -eq 1 ]]; then
          echo "Forwarding: localhost:$host_port -> guest:$guest_port"
        fi
      done
    fi

    # Control boot message visibility
    if [[ "''${argc_show_boot:-0}" -eq 1 ]]; then
      EXTRA_KERNEL_PARAMS="ignore_loglevel loglevel=7 systemd.show_status=yes"
    else
      EXTRA_KERNEL_PARAMS="quiet loglevel=0 systemd.show_status=no"
    fi

    # Set up TMPDIR with the pre-built Nix store image (symlink; drive is readonly)
    TMPDIR=$(mktemp -d nix-vm.XXXXXXXXXX --tmpdir)
    ln -s "$STORE_IMAGE" "$TMPDIR/store.img"

    echo "Starting VM..."
    echo "  Memory: ''${MEMORY}MB"
    echo "  Cores: $CORES"
    echo "  Disk: $NIX_DISK_IMAGE"
    if [[ "''${argc_show_boot:-0}" -eq 1 ]]; then
      echo "  Boot output: visible"
    else
      echo "  Boot output: hidden (use --show-boot to see)"
    fi
    if [[ -n "$QEMU_NET_OPTS" ]]; then
      echo "  Network: $QEMU_NET_OPTS"
    fi
    if [[ "''${argc_ephemeral:-0}" -eq 1 ]]; then
      echo "  Ephemeral mode: enabled"
    fi
    echo ""

    # Build the QEMU command — no shell passthrough, all options are explicit.
    # Each flag is commented for auditability.
    QEMU_ARGS=(
      # -- Hardening --
      -nodefaults        # Suppress all default devices (serial, parallel, VGA, floppy, etc.)
      -no-user-config    # Skip loading QEMU config files from the host
      ${
        if isLinuxHost then
          ''
            # seccomp sandbox: deny privilege escalation, process spawning,
            # obsolete syscalls, and resource control changes in the QEMU process.
            # Linux-only (uses seccomp); not available on macOS.
            -sandbox "on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny"''
        else
          ""
      }

      # -- Machine --
      -name ${targetHostname}
      -m "$MEMORY"       # Guest RAM
      -smp "$CORES"      # Guest CPU cores

      # -- Entropy --
      # Feed host entropy to the guest via virtio-rng
      -device virtio-rng-pci

      # -- Console --
      # Mux serial console with QEMU monitor on stdio; Ctrl-B switches to monitor
      -nographic
      -serial mon:stdio
      -echr 0x02

      # -- Network --
      # User-mode (SLiRP) networking — guest is NAT'd, no host bridge exposure
      -net "nic,netdev=user.0,model=virtio"
      -netdev "user,id=user.0''${QEMU_NET_OPTS:+,$QEMU_NET_OPTS}"

      # -- Storage --
      # Root disk (qcow2, writable)
      -drive "cache=writeback,file=$NIX_DISK_IMAGE,id=drive1,if=none,index=1,werror=report"
      -device "virtio-blk-pci,bootindex=1,drive=drive1,serial=root"
      # Nix store image (EROFS, readonly — guest uses overlayfs for writes)
      -drive "file=$TMPDIR/store.img,format=raw,readonly=on,id=drive2,if=none,index=2"
      -device "virtio-blk-pci,bootindex=2,drive=drive2"

      # -- Boot --
      # Direct kernel boot from the Nix closure (no bootloader, no env var overrides)
      -kernel ${toplevel}/kernel
      -initrd ${initrd}
      -append "$(cat ${toplevel}/kernel-params) init=${toplevel}/init regInfo=${regInfo}/registration console=${serialDevice},115200n8 $EXTRA_KERNEL_PARAMS"
    )

    # Snapshot mode: changes to drives are not persisted
    if [[ "''${argc_ephemeral:-0}" -eq 1 ]]; then
      QEMU_ARGS+=(-snapshot)
    fi

    if [[ "''${argc_verbose:-0}" -eq 1 ]]; then
      echo "QEMU binary: ${qemuBinary}"
      echo "QEMU args:"
      printf '  %s\n' "''${QEMU_ARGS[@]}"
      echo ""
    fi

    exec ${qemuBinary} "''${QEMU_ARGS[@]}"
  '';
}
