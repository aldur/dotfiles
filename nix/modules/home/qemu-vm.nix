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
      PORTS=()
      CONFIG_FILE=""
      INPUT_OVERRIDES=()
      MEMORY="${toString cfg.defaultMemory}"
      CORES="${toString cfg.defaultCores}"
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
        -p, --port PORT[:HOST]          Forward guest port to host (can be specified multiple times)
                                        Format: GUEST_PORT or GUEST_PORT:HOST_PORT
                                        Example: -p 22:2222 -p 80:8080
        -c, --config FILE               Path to custom NixOS configuration file
        -m, --memory SIZE               Memory size in MB (default: ${toString cfg.defaultMemory})
        --cores N                       Number of CPU cores (default: ${toString cfg.defaultCores})
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

        # Start VM with custom configuration
        qemu-vm -c ~/my-config.nix -p 22:2222

        # Rebuild and start with more resources
        qemu-vm --build --memory 8192 --cores 4 -p 22:2222

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
          -p|--port)
            PORTS+=("$2")
            shift 2
            ;;
          -c|--config)
            CONFIG_FILE="$2"
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

        # Build command as array
        BUILD_CMD=(nix build "${cfg.vmFlakeRef}.config.system.build.vm" --out-link "$VM_DIR/vm-result")

        # Add override arguments if present
        if [[ ''${#OVERRIDE_ARGS[@]} -gt 0 ]]; then
          BUILD_CMD+=("''${OVERRIDE_ARGS[@]}")
        fi

        # If custom config is provided, we need to build with an override
        if [[ -n "$CONFIG_FILE" ]]; then
          if [[ ! -f "$CONFIG_FILE" ]]; then
            echo "Error: Config file not found: $CONFIG_FILE"
            exit 1
          fi

          # Create a temporary flake that imports the custom config
          TEMP_DIR=$(mktemp -d)
          trap 'rm -rf "$TEMP_DIR"' EXIT

          cat > "$TEMP_DIR/flake.nix" << FLAKE_EOF
      {
        description = "Custom QEMU VM";

        inputs = {
          dotfiles.url = "${self}";
          nixpkgs.follows = "dotfiles/nixpkgs";
        };

        outputs = { self, dotfiles, nixpkgs }: {
          nixosConfigurations.qemu = nixpkgs.lib.nixosSystem {
            system = "$(nix eval --impure --expr 'builtins.currentSystem' --raw)";
            modules = [
              dotfiles.nixosConfigurations.qemu.config.system.nixos.modules
              (import $CONFIG_FILE)
            ];
          };
        };
      }
      FLAKE_EOF

          BUILD_CMD=(nix build "$TEMP_DIR#nixosConfigurations.qemu.config.system.build.vm" --out-link "$VM_DIR/vm-result")

          # Add override arguments to custom config build as well
          if [[ ''${#OVERRIDE_ARGS[@]} -gt 0 ]]; then
            # For custom config, we need to override on the dotfiles input
            DOTFILES_OVERRIDE_ARGS=()
            for ((i=0; i<''${#INPUT_OVERRIDES[@]}; i+=2)); do
              input_name="''${INPUT_OVERRIDES[i]}"
              flake_ref="''${INPUT_OVERRIDES[i+1]}"
              DOTFILES_OVERRIDE_ARGS+=("--override-input" "dotfiles/$input_name" "$flake_ref")
            done
            BUILD_CMD+=("''${DOTFILES_OVERRIDE_ARGS[@]}")
          fi
        fi

        if [[ "$VERBOSE" == "true" ]]; then
          echo "Running: ''${BUILD_CMD[*]}"
        fi

        "''${BUILD_CMD[@]}"

        # Link the VM image
        ln -sf "$VM_DIR/vm-result/nixos.qcow2" "$VM_IMAGE"
      fi

      # Build port forwarding arguments
      PORT_ARGS=()
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
        PORT_ARGS+=("-netdev" "user,id=net''${guest_port},hostfwd=tcp::''${host_port}-:''${guest_port}")
        PORT_ARGS+=("-device" "virtio-net-pci,netdev=net''${guest_port}")

        if [[ "$VERBOSE" == "true" ]]; then
          echo "Forwarding: localhost:$host_port -> guest:$guest_port"
        fi
      done

      # If no ports specified, set up default networking
      if [[ ''${#PORTS[@]} -eq 0 ]]; then
        PORT_ARGS+=("-nic" "user")
      fi

      # State directory for VM runtime
      STATE_DIR="$VM_DIR/state"
      mkdir -p "$STATE_DIR"

      # Determine system architecture for proper qemu binary
      ARCH="$(uname -m)"
      case "$ARCH" in
        x86_64)
          QEMU_BIN="qemu-system-x86_64"
          MACHINE_ARGS=("-machine" "type=q35,accel=kvm:hvf:tcg")
          ;;
        aarch64|arm64)
          QEMU_BIN="qemu-system-aarch64"
          MACHINE_ARGS=("-machine" "type=virt,accel=hvf:kvm:tcg")
          ;;
        *)
          echo "Unsupported architecture: $ARCH"
          exit 1
          ;;
      esac

      echo "Starting VM..."
      echo "  Memory: ''${MEMORY}MB"
      echo "  Cores: $CORES"
      echo "  Disk: $VM_IMAGE"
      echo "  Display: $DISPLAY_MODE"
      echo ""
      echo "Press Ctrl-A then X to quit (if using -nographic)"
      echo ""

      # Start the VM
      exec "$QEMU_BIN" \
        "''${MACHINE_ARGS[@]}" \
        -cpu host \
        -smp "$CORES" \
        -m "$MEMORY" \
        -drive file="$VM_IMAGE",if=virtio,format=qcow2 \
        "''${PORT_ARGS[@]}" \
        -display "$DISPLAY_MODE" \
        ''${DISPLAY_MODE:+-nographic} \
        -serial mon:stdio
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

    vmFlakeRef = mkOption {
      type = types.str;
      default = "${self}#nixosConfigurations.qemu";
      description = "Flake reference to the QEMU base host configuration";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ vmScript ];
  };
}
