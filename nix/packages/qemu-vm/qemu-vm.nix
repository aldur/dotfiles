{ pkgs, inputs,
  # Configurable defaults
  defaultVmDir ? "$HOME/.local/share/qemu-vm",
  defaultMemory ? 16384,
  defaultCores ? 8,
  defaultDiskSize ? 64,
  ...
}:

let
  inherit (inputs) self nixpkgs;

  # Determine target system based on host
  targetSystem = if pkgs.stdenv.hostPlatform.isAarch64 then "aarch64-linux" else "x86_64-linux";

  # Build the qemu NixOS configuration with proper VM settings
  qemuNixos = nixpkgs.lib.nixosSystem {
    system = targetSystem;
    specialArgs = {
      inputs = inputs // { inherit self; };
    };
    modules = [
      inputs.self.nixosModules.default
      "${self}/base_hosts/qemu/qemu.nix"
      ({ modulesPath, lib, ... }: {
        imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

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
      })
    ];
  };

  # Use the VM runner script that NixOS generates
  vmRunner = qemuNixos.config.system.build.vm;

in
pkgs.writeShellApplication {
  name = "qemu-vm";
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

    EXAMPLES:
      # Start VM with SSH forwarded to localhost:2222
      qemu-vm -p 22:2222

      # Start VM with custom location and multiple ports
      qemu-vm -d /data/my-vm -p 22:2222 -p 80:8080

      # Start with more resources
      qemu-vm --memory 8192 --cores 4 -p 22:2222

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
      export QEMU_KERNEL_PARAMS="console=ttyS0"
    elif [[ "$DISPLAY_MODE" == "gtk" ]]; then
      export QEMU_OPTS="$QEMU_OPTS -display gtk"
    fi

    echo "Starting VM..."
    echo "  Memory: ''${MEMORY}MB"
    echo "  Cores: $CORES"
    echo "  Disk: $NIX_DISK_IMAGE"
    echo "  Display: $DISPLAY_MODE"
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
      echo "NIX_DISK_IMAGE: $NIX_DISK_IMAGE"
      echo "Running NixOS VM runner..."
    fi

    # Run the VM using the NixOS-generated VM runner
    exec ${vmRunner}/bin/run-qemu-nixos-vm
  '';
}