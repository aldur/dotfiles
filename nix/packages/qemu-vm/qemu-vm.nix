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

  # Use the VM runner script that NixOS generates
  vmRunnerOriginal = qemuNixos.config.system.build.vm;

  # Remove unnecessary devices for terminal-only use
  vmRunner = pkgs.stdenv.mkDerivation {
    name = "qemu-vm-runner-minimal";
    src = vmRunnerOriginal;

    buildPhase = ''
      mkdir -p $out/bin

      # Remove unnecessary devices
      cat $src/bin/run-${targetHostname}-vm | \
        sed -e '/-device virtio-gpu-pci.*\\$/d' \
            -e '/-device usb-ehci.*\\$/d' \
            -e '/-device usb-kbd.*\\$/d' \
            -e '/-device usb-tablet.*\\$/d' \
            -e 's/console=tty0 //' \
            > $out/bin/run-${targetHostname}-vm

      chmod +x $out/bin/run-${targetHostname}-vm
    '';

    dontInstall = true;
  };

in
pkgs.writeArgcApplication {
  name = "qemu-vm";
  runtimeInputs = with pkgs; [
    qemu
    coreutils
    gnused
  ];
  passthru = {
    modules = baseModules;
  };
  text = ''
    # @describe Spawn a NixOS VM configured as the qemu base host
    # @option -d --dir <DIR> VM disk location [default: ${defaultVmDir}]
    # @option -p --port* <PORT> Forward guest port to host (GUEST_PORT[:HOST_PORT])
    # @option -m --memory <SIZE> Memory size in MB [default: ${toString defaultMemory}]
    # @option --cores <N> Number of CPU cores [default: ${toString defaultCores}]
    # @option --disk-size <SIZE> Disk size in GB [default: ${toString defaultDiskSize}]
    # @flag -v --verbose Verbose output
    # @flag --clean Remove existing VM state
    # @flag --ephemeral Do not write to the VM disk
    # @flag --show-boot Show boot console messages

    declare argc_dir argc_port argc_memory argc_cores argc_disk_size
    declare argc_verbose argc_clean argc_ephemeral argc_show_boot
    eval "$(argc --argc-eval "$0" "$@")"

    VM_DIR="''${argc_dir:-${defaultVmDir}}"
    MEMORY="''${argc_memory:-${toString defaultMemory}}"
    CORES="''${argc_cores:-${toString defaultCores}}"
    DISK_SIZE="''${argc_disk_size:-${toString defaultDiskSize}}"

    # Set up VM directory
    export NIX_DISK_IMAGE="$VM_DIR/nixos.qcow2"
    mkdir -p "$VM_DIR"

    # Handle clean flag
    if [[ "''${argc_clean:-0}" -eq 1 ]]; then
      echo "Cleaning VM state in $VM_DIR..."
      rm -f "$NIX_DISK_IMAGE"
    fi

    # Create disk if needed (the NixOS VM runner will handle this)
    if [[ ! -f "$NIX_DISK_IMAGE" ]]; then
      echo "VM disk will be created at: $NIX_DISK_IMAGE (''${DISK_SIZE}G)"
    fi

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

    # Set QEMU options as environment variables (used by NixOS VM runner)
    export QEMU_OPTS="-m $MEMORY -smp $CORES"

    if [[ -n "$QEMU_NET_OPTS" ]]; then
      export QEMU_NET_OPTS
    fi

    # Control boot message visibility
    if [[ "''${argc_show_boot:-0}" -eq 1 ]]; then
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

    if [[ "''${argc_ephemeral:-0}" -eq 1 ]]; then
      export QEMU_OPTS="$QEMU_OPTS -snapshot"
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
    if [[ -n "$QEMU_NET_OPTS" ]]; then
      echo "  Network: $QEMU_NET_OPTS"
    fi
    if [[ "''${argc_ephemeral:-0}" -eq 1 ]]; then
      echo "  Ephemeral mode: enabled"
    fi
    echo ""

    if [[ "''${argc_verbose:-0}" -eq 1 ]]; then
      echo "QEMU_OPTS: $QEMU_OPTS"
      echo "QEMU_KERNEL_PARAMS: ''${QEMU_KERNEL_PARAMS:-not set}"
      echo "NIX_DISK_IMAGE: $NIX_DISK_IMAGE"
      echo "Running NixOS VM runner..."
    fi

    exec ${vmRunner}/bin/run-${targetHostname}-vm
  '';
}
