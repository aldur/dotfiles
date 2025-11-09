{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

with lib;

let
  cfg = config.programs.qemu-vm;
  inherit (inputs) self;

  # Main VM spawn script
  vmScript = pkgs.writeShellApplication {
    name = "qemu-vm";
    runtimeInputs = with pkgs; [
      qemu
      coreutils
      gnused
    ];
    text = ''
      # Default values
      VM_DIR="${cfg.defaultVmDir}"
      FLAKE_REF="${cfg.vmFlakeRef}"
      PORTS=()
      INPUT_OVERRIDES=()
      MEMORY="${toString cfg.defaultMemory}"
      CORES="${toString cfg.defaultCores}"
      DISK_SIZE="${toString cfg.defaultDiskSize}"
      DISPLAY_MODE="none"
      VERBOSE=false

      # Parse command line arguments
      show_help() {
        cat << EOF
      Usage: qemu-vm [OPTIONS]

      Spawn a NixOS VM configured as the qemu base host.

      OPTIONS:
        -h, --help                      Show this help message
        -d, --dir DIR                   VM disk location (default: ${cfg.defaultVmDir})
        -f, --flake FLAKE               Flake reference for VM configuration (default: configured vmFlakeRef)
        -p, --port PORT[:HOST]          Forward guest port to host (can be specified multiple times)
                                        Format: GUEST_PORT or GUEST_PORT:HOST_PORT
                                        Example: -p 22:2222 -p 80:8080
        -m, --memory SIZE               Memory size in MB (default: ${toString cfg.defaultMemory})
        --cores N                       Number of CPU cores (default: ${toString cfg.defaultCores})
        --disk-size SIZE                Disk size in GB (default: ${toString cfg.defaultDiskSize})
        --override-input INPUT FLAKEREF Override a flake input (can be specified multiple times)
                                        Format: INPUT_NAME FLAKE_REF
                                        Example: --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable
        --gui                           Enable GUI (default: headless)
        -v, --verbose                   Verbose output
        --build                         Rebuild the VM image before starting
        --clean                         Remove existing VM state and rebuild

      EXAMPLES:
        # Start VM with SSH forwarded to localhost:2222
        qemu-vm -p 22:2222

        # Start VM with custom location and multiple ports
        qemu-vm -d /data/my-vm -p 22:2222 -p 80:8080

        # Use a custom flake for VM configuration
        qemu-vm --flake ~/my-custom-vm-flake -p 22:2222

        # Rebuild and start with more resources
        qemu-vm --build --memory 8192 --cores 4 --disk-size 128 -p 22:2222

        # Override nixpkgs input to use unstable
        qemu-vm --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable -p 22:2222

        # Override multiple inputs
        qemu-vm --override-input nixpkgs nixpkgs/nixos-unstable \\
                --override-input home-manager github:nix-community/home-manager \\
                -p 22:2222

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
          -f|--flake)
            FLAKE_REF="$2"
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
          --override-input)
            if [[ -z "''${2:-}" ]] || [[ -z "''${3:-}" ]]; then
              echo "Error: --override-input requires two arguments: INPUT_NAME FLAKE_REF"
              exit 1
            fi
            INPUT_OVERRIDES+=("$2" "$3")
            shift 3
            ;;
          --gui)
            DISPLAY_MODE="gtk"
            shift
            ;;
          -v|--verbose)
            VERBOSE=true
            shift
            ;;
          --build)
            BUILD=true
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

      # Ensure VM directory exists
      mkdir -p "$VM_DIR"

      # Handle clean flag
      if [[ "''${CLEAN:-false}" == "true" ]]; then
        echo "Cleaning VM state in $VM_DIR..."
        rm -rf "''${VM_DIR:?}"/*
        mkdir -p "$VM_DIR"
        BUILD=true
      fi

      # Build the VM if requested or if it doesn't exist
      VM_IMAGE="$VM_DIR/nixos.qcow2"
      if [[ "''${BUILD:-false}" == "true" ]] || [[ ! -f "$VM_IMAGE" ]]; then
        echo "Building VM image..."
        if [[ "$VERBOSE" == "true" ]]; then
          echo "Using flake: $FLAKE_REF"
        fi

        # Build input override arguments
        OVERRIDE_ARGS=()
        if [[ ''${#INPUT_OVERRIDES[@]} -gt 0 ]]; then
          for ((i=0; i<''${#INPUT_OVERRIDES[@]}; i+=2)); do
            input_name="''${INPUT_OVERRIDES[i]}"
            flake_ref="''${INPUT_OVERRIDES[i+1]}"
            OVERRIDE_ARGS+=("--override-input" "$input_name" "$flake_ref")
            if [[ "$VERBOSE" == "true" ]]; then
              echo "Overriding input: $input_name -> $flake_ref"
            fi
          done
        fi

        # Build the NixOS system configuration
        BUILD_CMD=(nix build "$FLAKE_REF#nixosConfigurations.qemu-nixos.config.system.build.toplevel" --out-link "$VM_DIR/system")

        # Add override arguments if present
        if [[ ''${#OVERRIDE_ARGS[@]} -gt 0 ]]; then
          BUILD_CMD+=("''${OVERRIDE_ARGS[@]}")
        fi

        if [[ "$VERBOSE" == "true" ]]; then
          echo "Running: ''${BUILD_CMD[*]}"
        fi

        "''${BUILD_CMD[@]}"

        # Extract kernel, initrd, and kernel params from the built system
        SYSTEM_PATH="$VM_DIR/system"
        KERNEL="$SYSTEM_PATH/kernel"
        INITRD="$SYSTEM_PATH/initrd"
        KERNEL_PARAMS=$(cat "$SYSTEM_PATH/kernel-params")

        if [[ "$VERBOSE" == "true" ]]; then
          echo "System built at: $SYSTEM_PATH"
          echo "Kernel: $KERNEL"
          echo "Initrd: $INITRD"
        fi
      fi

      # Create qcow2 disk if it doesn't exist
      if [[ ! -f "$VM_IMAGE" ]]; then
        echo "Creating disk image: $VM_IMAGE (''${DISK_SIZE}G)"
        qemu-img create -f qcow2 "$VM_IMAGE" "''${DISK_SIZE}G"
      fi

      # Get kernel, initrd, and params from built system
      SYSTEM_PATH="$VM_DIR/system"
      if [[ ! -d "$SYSTEM_PATH" ]]; then
        echo "Error: System not built at $SYSTEM_PATH"
        exit 1
      fi

      KERNEL="$SYSTEM_PATH/kernel"
      INITRD="$SYSTEM_PATH/initrd"
      KERNEL_PARAMS=$(cat "$SYSTEM_PATH/kernel-params")

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
      echo "  System: $SYSTEM_PATH"
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
  };

in
{
  options.programs.qemu-vm = {
    enable = mkEnableOption "QEMU VM spawner for base host configuration";

    defaultVmDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.local/share/qemu-vm";
      description = "Default directory for VM disk images and state";
    };

    defaultMemory = mkOption {
      type = types.int;
      default = 1024 * 16;
      description = "Default memory size in MB";
    };

    defaultCores = mkOption {
      type = types.int;
      default = 8;
      description = "Default number of CPU cores";
    };

    defaultDiskSize = mkOption {
      type = types.int;
      default = 64;
      description = "Default disk size in GB";
    };

    vmFlakeRef = mkOption {
      type = types.str;
      default = "path:${self}/base_hosts/qemu";
      description = "Flake reference to the QEMU base host flake";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ vmScript ];
  };
}
