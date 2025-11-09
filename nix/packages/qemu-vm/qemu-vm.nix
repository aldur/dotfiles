{ pkgs, inputs, lib, system,
  # Configurable defaults
  defaultVmDir ? "$HOME/.local/share/qemu-vm",
  defaultMemory ? 16384,
  defaultCores ? 8,
  defaultDiskSize ? 64,
  ...
}:

let
  inherit (inputs) self nixpkgs;

  # Build the qemu NixOS configuration
  # We need to evaluate the qemu flake's nixosConfiguration
  qemuNixos = nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";  # Target system for the VM
    specialArgs = {
      inputs = inputs // { inherit self; };
    };
    modules = [
      inputs.self.nixosModules.default
      "${self}/base_hosts/qemu/qemu.nix"
    ];
  };

  # Build the VM system
  vmSystem = qemuNixos.config.system.build.toplevel;

  # Create a derivation that prepares the VM files
  vmFiles = pkgs.runCommand "qemu-vm-files" {} ''
    mkdir -p $out
    ln -s ${vmSystem} $out/system
    ln -s ${vmSystem}/kernel $out/kernel
    ln -s ${vmSystem}/initrd $out/initrd
    cp ${vmSystem}/kernel-params $out/kernel-params
  '';

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
    SYSTEM_PATH="${vmFiles}/system"
    KERNEL="${vmFiles}/kernel"
    INITRD="${vmFiles}/initrd"
    KERNEL_PARAMS=$(cat "${vmFiles}/kernel-params")
    PORTS=()
    MEMORY="${toString defaultMemory}"
    CORES="${toString defaultCores}"
    DISK_SIZE="${toString defaultDiskSize}"
    DISPLAY_MODE="none"
    VERBOSE=false
    SNAPSHOT=false

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
      --snapshot                      Run in snapshot mode (changes not written to disk)

    EXAMPLES:
      # Start VM with SSH forwarded to localhost:2222
      qemu-vm -p 22:2222

      # Start VM with custom location and multiple ports
      qemu-vm -d /data/my-vm -p 22:2222 -p 80:8080

      # Start with more resources
      qemu-vm --memory 8192 --cores 4 --disk-size 128 -p 22:2222

      # Run in snapshot mode (changes not saved to disk)
      qemu-vm --snapshot -p 22:2222

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
        --snapshot)
          SNAPSHOT=true
          shift
          ;;
        *)
          echo "Unknown option: $1"
          show_help
          exit 1
          ;;
      esac
    done

    # Ensure VM directory exists
    mkdir -p "$VM_DIR"

    # Handle clean flag
    if [[ "''${CLEAN:-false}" == "true" ]]; then
      echo "Cleaning VM state in $VM_DIR..."
      rm -rf "''${VM_DIR:?}"/*
      mkdir -p "$VM_DIR"
    fi

    # Create qcow2 disk if it doesn't exist
    VM_IMAGE="$VM_DIR/nixos.qcow2"
    if [[ ! -f "$VM_IMAGE" ]]; then
      echo "Creating disk image: $VM_IMAGE (''${DISK_SIZE}G)"
      qemu-img create -f qcow2 "$VM_IMAGE" "''${DISK_SIZE}G"
    fi

    if [[ "$VERBOSE" == "true" ]]; then
      echo "System: $SYSTEM_PATH"
      echo "Kernel: $KERNEL"
      echo "Initrd: $INITRD"
      echo "Kernel params: $KERNEL_PARAMS"
    fi

    # Build QEMU arguments
    QEMU_ARGS=()

    # Determine system architecture for proper qemu binary
    ARCH="$(uname -m)"
    case "$ARCH" in
      x86_64)
        QEMU_BIN="qemu-system-x86_64"
        QEMU_ARGS+=("-machine" "type=q35,accel=kvm:hvf:tcg")
        ;;
      aarch64|arm64)
        QEMU_BIN="qemu-system-aarch64"
        QEMU_ARGS+=("-machine" "type=virt,accel=hvf:kvm:tcg")
        ;;
      *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
    esac

    # CPU and memory
    QEMU_ARGS+=("-cpu" "host")
    QEMU_ARGS+=("-smp" "$CORES")
    QEMU_ARGS+=("-m" "$MEMORY")

    # Kernel and initrd
    QEMU_ARGS+=("-kernel" "$KERNEL")
    QEMU_ARGS+=("-initrd" "$INITRD")
    QEMU_ARGS+=("-append" "init=$SYSTEM_PATH/init $KERNEL_PARAMS")

    # Disk
    QEMU_ARGS+=("-drive" "file=$VM_IMAGE,if=virtio,format=qcow2")

    # Snapshot mode
    if [[ "$SNAPSHOT" == "true" ]]; then
      QEMU_ARGS+=("-snapshot")
    fi

    # Networking - build port forwarding or use default
    if [[ ''${#PORTS[@]} -gt 0 ]]; then
      for port_spec in "''${PORTS[@]}"; do
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
        QEMU_ARGS+=("-netdev" "user,id=net''${guest_port},hostfwd=tcp::''${host_port}-:''${guest_port}")
        QEMU_ARGS+=("-device" "virtio-net-pci,netdev=net''${guest_port}")

        if [[ "$VERBOSE" == "true" ]]; then
          echo "Forwarding: localhost:$host_port -> guest:$guest_port"
        fi
      done
    else
      QEMU_ARGS+=("-nic" "user")
    fi

    # Display
    if [[ "$DISPLAY_MODE" == "none" ]]; then
      QEMU_ARGS+=("-nographic")
      QEMU_ARGS+=("-serial" "mon:stdio")
    else
      QEMU_ARGS+=("-display" "$DISPLAY_MODE")
    fi

    echo "Starting VM..."
    echo "  Memory: ''${MEMORY}MB"
    echo "  Cores: $CORES"
    echo "  Disk: $VM_IMAGE"
    if [[ "$SNAPSHOT" == "true" ]]; then
      echo "  Mode: snapshot (changes not saved)"
    fi
    echo "  System: $SYSTEM_PATH (pre-built)"
    echo "  Display: $DISPLAY_MODE"
    echo ""
    if [[ "$DISPLAY_MODE" == "none" ]]; then
      echo "Press Ctrl-A then X to quit"
    fi
    echo ""

    if [[ "$VERBOSE" == "true" ]]; then
      echo "Running: $QEMU_BIN ''${QEMU_ARGS[*]}"
    fi

    # Run QEMU
    exec "$QEMU_BIN" "''${QEMU_ARGS[@]}"
  '';
}