{
  pkgs,
  inputs,
  # Configurable defaults
  defaultVmDir ? "$HOME/.local/share/qemu-vm",
  defaultMemory ? 1024 * 16,
  defaultCores ? 8,
  defaultDiskSize ? 64,
  # Discard disk writes at exit unless `--persistent` is given.
  defaultEphemeral ? false,
  # Share the clipboard with the guest unless `--no-clipboard` is given.
  # The guest must run spice-vdagent (services.spice-vdagentd).
  defaultClipboard ? false,
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
  # qemu-common uses stdenv.hostPlatform as the *guest* system, so we
  # must pass the Linux (target) stdenv, not the host's (may be darwin).
  guestPkgs = import nixpkgs { system = targetSystem; };
  qemu-common = import "${nixpkgs}/nixos/lib/qemu-common.nix" {
    inherit (nixpkgs) lib;
    inherit (guestPkgs) stdenv;
  };
  # forceAccel: no TCG fallback. Without it, a broken hypervisor makes
  # QEMU emulate the whole CPU in C, with a larger attack surface, and
  # says nothing.
  qemuBinary = qemu-common.qemuBinaryWith {
    qemuPkg = pkgs.qemu;
    forceAccel = true;
  };
  serialDevice = qemu-common.qemuSerialDevice;
  # The bare binary, for the sandbox: qemuBinary carries the machine flags.
  qemuExe = builtins.head (nixpkgs.lib.splitString " " qemuBinary);
  # The store paths each sandboxed process may read: its own closure.
  qemuClosure = pkgs.closureInfo { rootPaths = [ pkgs.qemu ]; };
  gvproxyClosure = pkgs.closureInfo { rootPaths = [ pkgs.gvproxy ]; };
  # The two files QEMU boots. `toplevel/kernel` is a symlink to the first.
  kernelImage = "${qemuNixos.config.boot.kernelPackages.kernel}/${qemuNixos.config.system.boot.loader.kernelFile}";
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
    gvproxy
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
    # @option -f --file* <NAME=PATH> Expose a host file to the guest as /run/qemu-vm-files/NAME
    # @flag --ephemeral Do not write to the VM disk${if defaultEphemeral then " (default)" else ""}
    # @flag --persistent Write to the VM disk${if defaultEphemeral then "" else " (default)"}
    # @flag --show-boot Show boot console messages
    # @flag --gui Open a graphical display (virtio-gpu, keyboard, tablet)
    # @flag --clipboard Share the clipboard with the guest${
      if defaultClipboard then " (default)" else ""
    }
    # @flag --no-clipboard Do not share the clipboard${if defaultClipboard then "" else " (default)"}
    # @flag --no-network No network device and no gvproxy
    ${
      if isLinuxHost then
        ""
      else
        "# @flag --no-sandbox Do not confine QEMU and gvproxy with sandbox-exec"
    }

    declare argc_dir argc_port argc_memory argc_cores argc_disk_size
    declare argc_store_image argc_file
    declare argc_verbose argc_clean argc_ephemeral argc_persistent argc_show_boot argc_gui
    declare argc_clipboard argc_no_clipboard argc_no_sandbox argc_no_network
    eval "$(argc --argc-eval "$0" "$@")"

    EPHEMERAL=${if defaultEphemeral then "1" else "0"}
    [[ "''${argc_ephemeral:-0}" -eq 1 ]] && EPHEMERAL=1
    [[ "''${argc_persistent:-0}" -eq 1 ]] && EPHEMERAL=0
    CLIPBOARD=${if defaultClipboard then "1" else "0"}
    [[ "''${argc_clipboard:-0}" -eq 1 ]] && CLIPBOARD=1
    [[ "''${argc_no_clipboard:-0}" -eq 1 ]] && CLIPBOARD=0
    NETWORK=1
    [[ "''${argc_no_network:-0}" -eq 1 ]] && NETWORK=0
    if [[ "$NETWORK" -eq 0 && -n "''${argc_port:-}" ]]; then
      echo "--port needs a network; drop --no-network"
      exit 1
    fi

    VM_DIR="''${argc_dir:-${defaultVmDir}}"
    MEMORY="''${argc_memory:-${toString defaultMemory}}"
    CORES="''${argc_cores:-${toString defaultCores}}"
    DISK_SIZE="''${argc_disk_size:-${toString defaultDiskSize}}"
    NIX_DISK_IMAGE="$VM_DIR/nixos.qcow2"
    STORE_IMAGE="''${argc_store_image:-${nixStoreImage}/store.img}"
    # Canonical, like the disk image: the sandbox matches canonical paths.
    STORE_IMAGE=$(readlink -f "$STORE_IMAGE")

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

    # The guest network. gvproxy serves DHCP on 192.168.127.0/24 and
    # gives this MAC the fixed lease 192.168.127.2. The port forwards
    # below point at that address.
    GUEST_IP=192.168.127.2
    GUEST_MAC=5a:94:ef:e4:0c:ee

    # Port forwards, as `stack.forwards` entries of the gvproxy config,
    # and the host ports that the gvproxy sandbox lets it bind.
    FORWARDS=()
    BIND_RULES=()
    if [[ -n "''${argc_port:-}" ]]; then
      # argc returns a repeated option as an array.
      for port_spec in "''${argc_port[@]}"; do
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

        FORWARDS+=("    127.0.0.1:$host_port: $GUEST_IP:$guest_port")
        BIND_RULES+=("(allow network-bind network-inbound (local ip \"localhost:$host_port\"))")

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

    # The run directory: the store image symlink, the sockets, the gvproxy
    # config and log, and the sandbox profiles. Exported, so the
    # temporary disk of `--ephemeral` lands here too.
    # readlink -f: the sandbox profiles below match canonical paths, and
    # macOS keeps the user temp dir under /var, a symlink to /private/var.
    TMPDIR=$(readlink -f "$(mktemp -d nix-vm.XXXXXXXXXX --tmpdir)")
    export TMPDIR
    ln -s "$STORE_IMAGE" "$TMPDIR/store.img"

    # gvproxy listens here for the QEMU stream netdev.
    NET_SOCKET="$TMPDIR/net.sock"
    MONITOR_SOCKET="$TMPDIR/monitor.sock"
    GVPROXY_CONFIG="$TMPDIR/gvproxy.yaml"
    GVPROXY_LOG="$TMPDIR/gvproxy.log"
    # disable-guest-api and disable-host-nat come from
    # overlays/overrides/gvproxy-guest-isolation.patch; denyHostAccess
    # and loopbackForwardsOnly from gvproxy-host-isolation.patch. With
    # them the guest reaches no address of the host, on any platform.
    if [[ "$NETWORK" -eq 1 ]]; then
      {
        echo "log-level: $([[ "''${argc_verbose:-0}" -eq 1 ]] && echo info || echo warning)"
        echo "log-file: $GVPROXY_LOG"
        echo "disable-guest-api: true"
        echo "disable-host-nat: true"
        echo "interfaces:"
        echo "  qemu: unix://$NET_SOCKET"
        echo "stack:"
        echo "  denyHostAccess: true"
        echo "  loopbackForwardsOnly: true"
        echo "  dhcpStaticLeases:"
        echo "    $GUEST_IP: $GUEST_MAC"
        echo "  forwards:"
        printf '%s\n' "''${FORWARDS[@]}"
      } > "$GVPROXY_CONFIG"
    fi

    # macOS: confine both processes with the Seatbelt sandbox. The
    # profiles deny by default and allow exactly what each process was
    # seen to need: its closure, the run directory files it uses, and
    # the files it was given. QEMU has no host network at all, only
    # the two unix sockets, and cannot fork or exec: the monitor's
    # `migrate exec:` lands on the sandbox. gvproxy binds only the
    # `--port` forwards, dials no address of the host, and reaches no
    # unix socket but the resolver. A later rule wins over an earlier
    # one. Seatbelt matches canonical paths, hence the readlink -f.
    #
    # The allowlists come from the denials the unified log reports:
    #   log stream --predicate 'sender == "Sandbox"'
    # Every rule answers a denial that broke something. What stays
    # denied is what the processes work without: logging and
    # diagnostics services, OS version and CPU feature sysctls (gvproxy
    # only; QEMU asserts on those), the working directory, and for the
    # display DiskArbitration, directory services, the Dock, and the
    # GPU, which leaves Cocoa on software rendering.
    QEMU_WRAP=()
    GVPROXY_WRAP=()
    SANDBOX=${if isLinuxHost then "0" else "1"}
    [[ "''${argc_no_sandbox:-0}" -eq 1 ]] && SANDBOX=0
    if [[ "$SANDBOX" -eq 1 ]]; then
      # The terminal of the serial console, if there is one.
      TTY_DEV=$(tty 2>/dev/null || true)
      TTY_RULE=""
      [[ "$TTY_DEV" == /dev/* ]] && TTY_RULE="(literal \"$TTY_DEV\")"
      # The run directory, escaped for a regex.
      TMPDIR_RE=$(printf '%s' "$TMPDIR" | sed 's/[.[\*^$]/\\&/g')
      # One (subpath ...) per store path of a closure.
      store_paths() {
        while read -r path; do printf '(subpath "%s") ' "$path"; done < "$1/store-paths"
      }
      # One (literal ...) per ancestor directory of a path: QEMU stats
      # its way down to the files it opens.
      ancestors() {
        local path=$1
        while [[ "$path" != / ]]; do
          path=$(dirname "$path")
          printf '(literal "%s") ' "$path"
        done
      }
      FILE_READ_RULES=()
      for file_spec in "''${argc_file[@]:-}"; do
        [[ -n "$file_spec" ]] || continue
        FILE_READ_RULES+=("(allow file-read* (literal \"$(readlink -f "''${file_spec#*=}")\"))")
      done
      {
        echo "(version 1)"
        echo "(deny default)"
        echo "(allow process-exec (literal \"${qemuExe}\"))"
        echo "(allow file-read* file-map-executable $(store_paths ${qemuClosure}))"
        # dyld reads the root directory; libSystem reads two sysctls at
        # init. QEMU asserts unless the CPU feature sysctls answer, and
        # sizes its coroutine stacks from the page size.
        echo "(allow file-read* (literal \"/\"))"
        echo "(allow sysctl-read (sysctl-name \"kern.bootargs\") (sysctl-name \"security.mac.lockdown_mode_state\") (sysctl-name-prefix \"hw.optional.\") (sysctl-name \"hw.pagesize_compat\") (sysctl-name \"hw.cachelinesize\") (sysctl-name \"machdep.cpu.brand_string\"))"
        echo "(allow file-read* (literal \"${toplevel}/kernel\") (literal \"${kernelImage}\") (literal \"${initrd}\"))"
        echo "(allow file-read* (literal \"$TMPDIR/store.img\") (literal \"$STORE_IMAGE\"))"
        echo "(allow file-read-metadata $(ancestors "$TMPDIR/store.img") $(ancestors "$STORE_IMAGE") $(ancestors "$NIX_DISK_IMAGE") $(ancestors "${qemuExe}") $(ancestors "${kernelImage}") $(ancestors "${initrd}"))"
        echo "(allow file-read* file-write* (literal \"$NIX_DISK_IMAGE\"))"
        printf '%s\n' "''${FILE_READ_RULES[@]}"
        # /dev/null: QEMU opens it read-write to probe file locking.
        echo "(allow file-read* file-write* (literal \"/dev/null\"))"
        # Entropy for virtio-rng.
        echo "(allow file-read* (literal \"/dev/urandom\"))"
        echo "(allow file-read* file-write* file-ioctl $TTY_RULE)"
        # The sockets: QEMU serves the monitor and dials gvproxy.
        echo "(allow file-write* (literal \"$MONITOR_SOCKET\"))"
        echo "(allow network-bind network-inbound (literal \"$MONITOR_SOCKET\"))"
        if [[ "$NETWORK" -eq 1 ]]; then
          echo "(allow network-outbound (literal \"$NET_SOCKET\"))"
        fi
        if [[ "$EPHEMERAL" -eq 1 ]]; then
          # The temporary disk of -snapshot.
          echo "(allow file-read* file-write* (regex #\"^$TMPDIR_RE/vl\\.\"))"
        fi
        if [[ "''${argc_gui:-0}" -eq 1 ]]; then
          # The Cocoa display: the window server, rendering, input, and
          # the pasteboard for --clipboard.
          # virtio-gpu backs its memory with a memfd, a file on macOS.
          echo "(allow file-read* file-write* (regex #\"^$TMPDIR_RE/memfd-\"))"
          # AppKit loads bundles, nibs and ICU data from the system volume,
          # and the appearance from the system-wide defaults.
          echo "(allow file-read-metadata (literal \"/System\") (literal \"/usr\") (literal \"/usr/share\") (literal \"/Library\") (literal \"/Library/Preferences\"))"
          echo "(allow file-read* (subpath \"/System/Library\") (subpath \"/usr/share/icu\") (literal \"/Library/Preferences/.GlobalPreferences.plist\"))"
          # The objc runtime dlopens this one library outside the dyld cache.
          echo "(allow file-read-metadata (literal \"/usr/lib\"))"
          echo "(allow file-read* file-map-executable (literal \"/usr/lib/libobjc-trampolines.dylib\"))"
          echo "(allow mach-lookup"
          echo "  (global-name \"com.apple.windowserver.active\")"
          echo "  (global-name \"com.apple.windowmanager.server\")"
          echo "  (global-name \"com.apple.CARenderServer\")"
          echo "  (global-name \"com.apple.pasteboard.1\")"
          echo "  (global-name \"com.apple.iohideventsystem\")"
          echo "  (global-name \"com.apple.hiservices-xpcservice\")"
          echo "  (global-name \"com.apple.coreservices.launchservicesd\")"
          # Without the database, LaunchServices retries its registration in a
          # tight loop.
          echo "  (global-name \"com.apple.lsd.mapdb\")"
          echo "  (global-name \"com.apple.lsd.modifydb\"))"
          echo "(allow iokit-open-user-client (iokit-user-client-class \"IOSurfaceRootUserClient\") (iokit-user-client-class \"IOHIDParamUserClient\"))"
        fi
      } > "$TMPDIR/qemu.sb"
      [[ "$NETWORK" -eq 1 ]] && {
        echo "(version 1)"
        echo "(deny default)"
        echo "(allow process-exec (literal \"${pkgs.gvproxy}/bin/gvproxy\"))"
        echo "(allow file-read* file-map-executable $(store_paths ${gvproxyClosure}))"
        # dyld reads the root directory; libSystem reads two sysctls at
        # init; the Go runtime reads two more.
        echo "(allow file-read* (literal \"/\"))"
        echo "(allow sysctl-read (sysctl-name \"kern.bootargs\") (sysctl-name \"security.mac.lockdown_mode_state\") (sysctl-name \"hw.ncpu\") (sysctl-name \"hw.pagesize_compat\"))"
        # denyHostAccess lists the interface addresses through the routing table.
        echo "(allow sysctl-read (sysctl-name-prefix \"net.routetable.\"))"
        echo "(allow file-read* (literal \"$GVPROXY_CONFIG\"))"
        # The log is opened read-write.
        echo "(allow file-read* file-write* (literal \"$GVPROXY_LOG\"))"
        echo "(allow file-write* (literal \"$NET_SOCKET\"))"
        # The resolver: /etc/resolv.conf is a symlink through /var into
        # /var/run, and Go stats it before choosing how to resolve.
        echo "(allow file-read-metadata (literal \"/etc\") (literal \"/var\"))"
        echo "(allow file-read* (literal \"/private/etc/resolv.conf\") (literal \"/private/var/run/resolv.conf\"))"
        # The DHCP server draws its transaction IDs from here.
        echo "(allow file-read* (literal \"/dev/urandom\"))"
        echo "(allow network-bind network-inbound (literal \"$NET_SOCKET\"))"
        echo "(allow network-outbound (remote ip \"*:*\"))"
        # DNS goes through the system resolver, a unix socket.
        echo "(allow network-outbound (literal \"/private/var/run/mDNSResponder\"))"
        # "localhost" covers every address of the host, not only loopback.
        echo "(deny network-outbound (remote ip \"localhost:*\"))"
        printf '%s\n' "''${BIND_RULES[@]}"
      } > "$TMPDIR/gvproxy.sb"
      QEMU_WRAP=(/usr/bin/sandbox-exec -f "$TMPDIR/qemu.sb")
      GVPROXY_WRAP=(/usr/bin/sandbox-exec -f "$TMPDIR/gvproxy.sb")
    fi

    echo "Starting VM..."
    echo "  Memory: ''${MEMORY}MB"
    echo "  Cores: $CORES"
    echo "  Disk: $NIX_DISK_IMAGE"
    if [[ "''${argc_show_boot:-0}" -eq 1 ]]; then
      echo "  Boot output: visible"
    else
      echo "  Boot output: hidden (use --show-boot to see)"
    fi
    if [[ "$NETWORK" -eq 1 ]]; then
      echo "  Network: gvproxy, guest $GUEST_IP"
    else
      echo "  Network: none"
    fi
    echo "  Monitor: nc -U $MONITOR_SOCKET"
    if [[ "$SANDBOX" -eq 1 ]]; then
      echo "  Sandbox: sandbox-exec (use --no-sandbox to disable)"
    fi
    if [[ "$EPHEMERAL" -eq 1 ]]; then
      echo "  Ephemeral mode: enabled"
    fi
    if [[ "''${argc_gui:-0}" -eq 1 ]]; then
      echo "  Display: graphical window (serial console stays on this terminal)"
    fi
    if [[ "$CLIPBOARD" -eq 1 ]]; then
      echo "  Clipboard: shared"
    fi

    # Files for the guest. QEMU exposes them through fw_cfg. The guest
    # module (modules/nixos/qemu-guest.nix) copies them to
    # /run/qemu-vm-files at boot.
    FILE_ARGS=()
    if [[ -n "''${argc_file:-}" ]]; then
      for file_spec in "''${argc_file[@]}"; do
        if [[ "$file_spec" =~ ^([A-Za-z0-9._-]+)=(.+)$ ]]; then
          file_name="''${BASH_REMATCH[1]}"
          file_path="''${BASH_REMATCH[2]}"
        else
          echo "Invalid file specification: $file_spec (want NAME=PATH)"
          exit 1
        fi
        if [[ ! -r "$file_path" ]]; then
          echo "Cannot read file: $file_path"
          exit 1
        fi
        # Canonical: the sandbox matches canonical paths.
        file_path=$(readlink -f "$file_path")
        FILE_ARGS+=(-fw_cfg "name=opt/qemu-vm/$file_name,file=$file_path")
        echo "  File: $file_path -> /run/qemu-vm-files/$file_name"
      done
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
      # The serial console is on this terminal. signal=off gives Ctrl-C
      # to the guest. The monitor runs host commands, so it is not on
      # the terminal: nothing the guest writes to the terminal can reach
      # it. Connect with `nc -U`.
      -chardev "stdio,id=console,signal=off"
      -serial chardev:console
      -monitor "unix:$MONITOR_SOCKET,server=on,wait=off"

      # -- Storage --
      # Root disk (qcow2, writable). The explicit format stops QEMU from
      # probing the image, which a guest could otherwise shape.
      -drive "cache=writeback,file=$NIX_DISK_IMAGE,format=qcow2,id=drive1,if=none,index=1,werror=report"
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

    # -- Network --
    # gvproxy does NAT, DHCP, DNS, and the port forwards in its own
    # process, with the memory-safe stack of gVisor. QEMU only holds a
    # unix socket to it, so it has no in-process SLiRP. `--no-network`
    # leaves the guest without a NIC.
    if [[ "$NETWORK" -eq 1 ]]; then
      QEMU_ARGS+=(
        -device "virtio-net-pci,netdev=net0,mac=$GUEST_MAC"
        -netdev "stream,id=net0,server=off,addr.type=unix,addr.path=$NET_SOCKET"
      )
    fi

    # -- Display --
    # `-nodefaults` above gives the guest no GPU. `--gui` adds a virtio GPU,
    # a keyboard, and an absolute pointer, and opens the native display of
    # the host. Without it, the VM has only the serial console.
    if [[ "''${argc_gui:-0}" -eq 1 ]]; then
      QEMU_ARGS+=(
        -display ${if isLinuxHost then "gtk" else "cocoa"}
        -device virtio-gpu-pci
        -device virtio-keyboard-pci
        -device virtio-tablet-pci
      )
    else
      QEMU_ARGS+=(-display none)
    fi

    # -- Clipboard --
    # QEMU speaks the vdagent protocol itself, so no SPICE is needed. The
    # Cocoa display syncs its clipboard with the guest agent. The GTK
    # display does not: nixpkgs builds QEMU without `gtk-clipboard`.
    if [[ "$CLIPBOARD" -eq 1 ]]; then
      QEMU_ARGS+=(
        -device virtio-serial-pci
        -chardev "qemu-vdagent,id=vdagent,name=vdagent,clipboard=on"
        -device "virtserialport,chardev=vdagent,name=com.redhat.spice.0"
      )
    fi

    QEMU_ARGS+=("''${FILE_ARGS[@]}")

    # Snapshot mode: changes to drives are not persisted
    if [[ "$EPHEMERAL" -eq 1 ]]; then
      QEMU_ARGS+=(-snapshot)
    fi

    if [[ "''${argc_verbose:-0}" -eq 1 ]]; then
      echo "QEMU binary: ${qemuBinary}"
      echo "QEMU args:"
      printf '  %s\n' "''${QEMU_ARGS[@]}"
      if [[ "$NETWORK" -eq 1 ]]; then
        echo "gvproxy config: $GVPROXY_CONFIG"
        echo "gvproxy log: $GVPROXY_LOG"
      fi
      echo ""
    fi

    # gvproxy must listen before QEMU connects. QEMU runs as a child, not
    # with exec, so the trap can stop gvproxy at exit.
    # The log-file setting covers gvproxy's own logger only. Its TCP
    # proxy logs dial errors to stderr, so send that to the file too and
    # keep the terminal for the serial console.
    GVPROXY_PID=""
    # gvproxy exits by itself when QEMU closes the socket, so the kill
    # may find nothing.
    trap 'if [[ -n "$GVPROXY_PID" ]]; then kill "$GVPROXY_PID" 2>/dev/null || true; fi; rm -rf "$TMPDIR"' EXIT
    if [[ "$NETWORK" -eq 1 ]]; then
      "''${GVPROXY_WRAP[@]}" gvproxy -config "$GVPROXY_CONFIG" >>"$GVPROXY_LOG" 2>&1 &
      GVPROXY_PID=$!
      for _ in $(seq 50); do
        [[ -S "$NET_SOCKET" ]] && break
        sleep 0.1
      done
      if [[ ! -S "$NET_SOCKET" ]]; then
        echo "gvproxy did not open $NET_SOCKET; see $GVPROXY_LOG"
        exit 1
      fi
    fi

    "''${QEMU_WRAP[@]}" ${qemuBinary} "''${QEMU_ARGS[@]}"
  '';
}
