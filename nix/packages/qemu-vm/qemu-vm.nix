{
  pkgs,
  inputs,
  # Configurable defaults
  defaultVmDir ? "$HOME/.local/share/qemu-vm",
  defaultMemory ? 16384,
  defaultCores ? 8,
  defaultDiskSize ? 64,
  defaultQemuModule ? ../../base_hosts/qemu/qemu.nix,
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
      defaultQemuModule
      (
        {
          config,
          modulesPath,
          lib,
          options,
          ...
        }:
        {
          imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

          virtualisation = {
            diskSize = defaultDiskSize * 1024;
            cores = defaultCores;
            memorySize = defaultMemory;
            writableStoreUseTmpfs = false;
            useBootLoader = false;

            # We need to remove the `xchg` and `shared` directories,
            # so we need to re-define this option without them.
            sharedDirectories = lib.mkForce {
              nix-store = lib.mkIf config.virtualisation.mountHostNixStore {
                source = builtins.storeDir;
                # Always mount this to /nix/.ro-store because we never want to actually
                # write to the host Nix Store.
                target = "/nix/.ro-store";
                securityModel = "none";
              };
              certs = lib.mkIf config.virtualisation.useHostCerts {
                source = ''"$TMPDIR"/certs'';
                target = "/etc/ssl/certs";
                securityModel = "none";
              };
            };

            # Disable graphics completely for terminal-only use
            graphics = false;

            # Build for the host system
            qemu.package = pkgs.qemu;
            host.pkgs = pkgs;
          };

          # Remove xchg/shared filesystem mounts since we removed the virtfs devices
          # Use mkForce with null to completely remove these mount points
          fileSystems."/tmp/xchg" = lib.mkForce null;
          fileSystems."/tmp/shared" = lib.mkForce null;
        }
      )
    ];
  };

  # Use the VM runner script that NixOS generates
  vmRunnerOriginal = qemuNixos.config.system.build.vm;

  # Remove unnecessary devices for terminal-only use
  vmRunner = pkgs.stdenv.mkDerivation {
    name = "qemu-vm-runner-minimal";
    src = vmRunnerOriginal;

    buildPhase = ''
      mkdir -p $out/bin

      # Remove BOTH virtfs mounts (xchg and shared) and unnecessary devices
      cat $src/bin/run-qemu-nixos-vm | \
        sed -e '/-virtfs.*mount_tag=xchg.*\\$/d' \
            -e '/-virtfs.*mount_tag=shared.*\\$/d' \
            -e '/-device virtio-keyboard.*\\$/d' \
            -e '/-device virtio-gpu-pci.*\\$/d' \
            -e '/-device usb-ehci.*\\$/d' \
            -e '/-device usb-kbd.*\\$/d' \
            -e '/-device usb-tablet.*\\$/d' \
            -e 's/console=tty0 //' \
            > $out/bin/run-qemu-nixos-vm

      chmod +x $out/bin/run-qemu-nixos-vm
    '';

    installPhase = "true"; # buildPhase does everything
  };

in
pkgs.writeShellApplication {
  name = "qemu-vm";
  passthru = {
    modules = baseModules;
  };
  runtimeInputs = with pkgs; [
    qemu
    coreutils
    gnused
  ];
  text = ''
    # Default values
    VM_DIR="${defaultVmDir}"
    PORTS=()
    MEMORY="${toString defaultMemory}"
    CORES="${toString defaultCores}"
    DISK_SIZE="${toString defaultDiskSize}"
    DISPLAY_MODE="none"
    VERBOSE=false
    CLEAN=false
    SHOW_BOOT=false

    # Parse command line arguments
    show_help() {
      cat << EOF
    Usage: qemu-vm [OPTIONS]

    Spawn a NixOS VM configured as the qemu base host.

    OPTIONS:
      -h, --help                      Show this help message
      -d, --dir DIR                   VM disk location (default: ${defaultVmDir})
      -p, --port PORT[:HOST]          Forward guest port to host (can be specified multiple times)
                                      Format: GUEST_PORT or GUEST_PORT:HOST_PORT
                                      Example: -p 22:2222 -p 80:8080
      -m, --memory SIZE               Memory size in MB (default: ${toString defaultMemory})
      --cores N                       Number of CPU cores (default: ${toString defaultCores})
      --disk-size SIZE                Disk size in GB (default: ${toString defaultDiskSize})
      --gui                           Enable GUI (default: headless)
      -v, --verbose                   Verbose output
      --clean                         Remove existing VM state
      --show-boot                     Show boot console messages (default: hidden)

    EXAMPLES:
      # Start VM with SSH forwarded to localhost:2222
      qemu-vm -p 22:2222

      # Start VM with custom location and multiple ports
      qemu-vm -d /data/my-vm -p 22:2222 -p 80:8080

      # Start with more resources
      qemu-vm --memory 8192 --cores 4 -p 22:2222

      # Show boot console messages
      qemu-vm --show-boot -p 22:2222

    EOF
    }

    # Parse arguments
    while [[ $# -gt 0 ]]; do
      case $1 in
        -h|--help)
          show_help
          exit 0
          ;;
        -d|--dir)
          VM_DIR="$2"
          shift 2
          ;;
        -p|--port)
          PORTS+=("$2")
          shift 2
          ;;
        -m|--memory)
          MEMORY="$2"
          shift 2
          ;;
        --cores)
          CORES="$2"
          shift 2
          ;;
        --disk-size)
          DISK_SIZE="$2"
          shift 2
          ;;
        --gui)
          DISPLAY_MODE="gtk"
          shift
          ;;
        -v|--verbose)
          VERBOSE=true
          shift
          ;;
        --clean)
          CLEAN=true
          shift
          ;;
        --show-boot)
          SHOW_BOOT=true
          shift
          ;;
        *)
          echo "Unknown option: $1"
          show_help
          exit 1
          ;;
      esac
    done

    # Set up VM directory
    export NIX_DISK_IMAGE="$VM_DIR/nixos.qcow2"
    mkdir -p "$VM_DIR"

    # Handle clean flag
    if [[ "$CLEAN" == "true" ]]; then
      echo "Cleaning VM state in $VM_DIR..."
      rm -f "$NIX_DISK_IMAGE"
    fi

    # Create disk if needed (the NixOS VM runner will handle this)
    if [[ ! -f "$NIX_DISK_IMAGE" ]]; then
      echo "VM disk will be created at: $NIX_DISK_IMAGE (''${DISK_SIZE}G)"
    fi

    # Build QEMU network arguments
    QEMU_NET_OPTS=""
    if [[ ''${#PORTS[@]} -gt 0 ]]; then
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

        if [[ "$VERBOSE" == "true" ]]; then
          echo "Forwarding: localhost:$host_port -> guest:$guest_port"
        fi
      done
    fi

    # Set QEMU options as environment variables (used by NixOS VM runner)
    export QEMU_OPTS="-m $MEMORY -smp $CORES"

    if [[ -n "$QEMU_NET_OPTS" ]]; then
      export QEMU_NET_OPTS
    fi

    if [[ "$DISPLAY_MODE" == "none" ]]; then
      export QEMU_OPTS="$QEMU_OPTS -nographic"
    elif [[ "$DISPLAY_MODE" == "gtk" ]]; then
      export QEMU_OPTS="$QEMU_OPTS -display gtk"
    fi

    # Control boot message visibility
    if [[ "$SHOW_BOOT" == "true" ]]; then
      # Force showing all boot messages
      # loglevel=7 shows all messages including debug (overrides quiet)
      # systemd.show_status=yes forces systemd to show service status
      # ignore_loglevel forces all kernel messages to be printed
      export QEMU_KERNEL_PARAMS="ignore_loglevel loglevel=7 systemd.show_status=yes"
    else
      # Suppress boot messages with quiet and minimal loglevel
      # quiet suppresses most kernel messages
      # loglevel=0 only shows emergency messages (panic only)
      # systemd.show_status=no suppresses systemd service messages
      export QEMU_KERNEL_PARAMS="quiet loglevel=0 systemd.show_status=no"
    fi

    echo "Starting VM..."
    echo "  Memory: ''${MEMORY}MB"
    echo "  Cores: $CORES"
    echo "  Disk: $NIX_DISK_IMAGE"
    echo "  Display: $DISPLAY_MODE"
    if [[ "$SHOW_BOOT" == "true" ]]; then
      echo "  Boot output: visible"
    else
      echo "  Boot output: hidden (use --show-boot to see)"
    fi
    if [[ -n "$QEMU_NET_OPTS" ]]; then
      echo "  Network: $QEMU_NET_OPTS"
    fi
    echo ""
    if [[ "$DISPLAY_MODE" == "none" ]]; then
      echo "Press Ctrl-A then X to quit"
    fi
    echo ""

    if [[ "$VERBOSE" == "true" ]]; then
      echo "QEMU_OPTS: $QEMU_OPTS"
      echo "QEMU_KERNEL_PARAMS: ''${QEMU_KERNEL_PARAMS:-not set}"
      echo "NIX_DISK_IMAGE: $NIX_DISK_IMAGE"
      echo "Running NixOS VM runner..."
    fi

    # Run the VM using the NixOS-generated VM runner
    exec ${vmRunner}/bin/run-qemu-nixos-vm
  '';
}
