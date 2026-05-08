{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardening;
in
{
  options.hardening = {
    kernelModules.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Blacklist niche, legacy, and known-buggy kernel modules to reduce
        attack surface. Each entry in `boot.blacklistedKernelModules` is also
        mapped to `install <mod> /bin/false` in /etc/modprobe.d so manual
        `modprobe` is blocked too, matching Kicksecure security-misc semantics.
        On activation, any already-loaded blacklisted module is unloaded.
      '';
    };

    sysctl.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Apply kernel and network sysctl hardening: pointer/dmesg restrictions,
        ASLR entropy, TOCTOU link protections, ptrace scope, BPF JIT hardening,
        TCP syncookies/rfc1337, rp_filter, no ICMP redirects, no source routing.
      '';
    };

    minimizeWrappers.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Disable seldom-used setuid/setgid wrappers (su, sudoedit, sg, newgrp,
        pkexec, newuidmap, newgidmap, fusermount[3]). Each entry is set with
        `lib.mkDefault`, so modules that need a specific wrapper can re-enable
        it with a plain assignment (rootless Docker re-enables newuidmap,
        newgidmap, fusermount, and fusermount3).
      '';
    };
  };

  config = lib.mkMerge [
    {
      systemd.coredump.enable = false;

      security.pam.loginLimits = [
        {
          domain = "*";
          type = "hard";
          item = "core";
          value = "0";
        }
      ];

      boot.tmp.cleanOnBoot = true;
    }

    (lib.mkIf cfg.sysctl.enable {
      boot.kernel.sysctl = {
        "kernel.core_pattern" = "|/bin/false";
        "fs.suid_dumpable" = 0;

        # Filesystem link protections (TOCTOU mitigation)
        "fs.protected_hardlinks" = 1;
        "fs.protected_symlinks" = 1;
        "fs.protected_fifos" = 2;
        "fs.protected_regular" = 2;

        # Kernel hardening
        "kernel.kptr_restrict" = 2;
        "kernel.dmesg_restrict" = 1;
        "kernel.yama.ptrace_scope" = 2;
        "kernel.perf_event_paranoid" = 3;
        "kernel.kexec_load_disabled" = 1;
        "kernel.sysrq" = 0;
        "kernel.randomize_va_space" = 2;
        "vm.unprivileged_userfaultfd" = 0;
        "dev.tty.ldisk_autoload" = 0;
        "kernel.unprivileged_bpf_disabled" = 1;
        "net.core.bpf_jit_harden" = 2;

        # ASLR entropy (x86_64 maxima)
        "vm.mmap_rnd_bits" = 32;
        "vm.mmap_rnd_compat_bits" = 16;

        # Network hardening (workstation, not a router)
        "net.ipv4.tcp_syncookies" = 1;
        "net.ipv4.tcp_rfc1337" = 1;
        "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
        # Loose mode: avoids asymmetric-routing drops on Tailscale exit nodes.
        "net.ipv4.conf.all.rp_filter" = 2;
        "net.ipv4.conf.default.rp_filter" = 2;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.all.secure_redirects" = 0;
        "net.ipv4.conf.default.secure_redirects" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.default.send_redirects" = 0;
        "net.ipv4.conf.all.accept_source_route" = 0;
        "net.ipv4.conf.default.accept_source_route" = 0;
        "net.ipv4.conf.all.log_martians" = 1;
        "net.ipv4.conf.default.log_martians" = 1;
        "net.ipv6.conf.all.accept_redirects" = 0;
        "net.ipv6.conf.default.accept_redirects" = 0;
        "net.ipv6.conf.all.accept_source_route" = 0;
        "net.ipv6.conf.default.accept_source_route" = 0;
      };
    })

    (lib.mkIf cfg.kernelModules.enable {
      boot.blacklistedKernelModules = [
        # --- Mitigation against CVE-2026-31431/copy.fail ---
        "algif_aead"
        # --- /Mitigation against CVE-2026-31431/copy.fail ---

        # --- Mitigation against dirtyfrag ---
        "esp4"
        "esp6"
        "rxrpc"
        # --- /Mitigation against dirtyfrag ---

        # Selections sourced from Kicksecure security-misc
        # 30_security-misc_disable.conf, with Bluetooth, USB video,
        # Thunderbolt, network filesystems, MEI and joydev kept enabled.
        # https://github.com/Kicksecure/security-misc/blob/master/etc/modprobe.d/30_security-misc_disable.conf

        # --- Obscure / legacy network protocols ---
        "dccp" # Datagram Congestion Control Protocol
        "sctp"
        "sctp_diag"
        "rds" # Reliable Datagram Sockets
        "rds_rdma"
        "rds_tcp"
        "tipc" # Transparent Inter-Process Communication
        "tipc_diag"
        "n-hdlc" # High-level Data Link Control
        "ax25" # Amateur radio
        "netrom" # Amateur radio
        "x25"
        "rose" # Amateur radio
        "decnet"
        "econet" # Acorn Econet
        "af_802154" # IEEE 802.15.4
        "ipx" # Novell IPX
        "appletalk"
        "psnap" # Subnetwork Access Protocol
        "p8023" # Novell raw IEEE 802.3
        "p8022" # IEEE 802.2
        "eepro100" # Replaced legacy Intel ethernet
        "eth1394" # FireWire ethernet emulation
        # --- /Obscure / legacy network protocols ---

        # --- ATM ---
        "atm"
        "ueagle-atm"
        "usbatm"
        "xusbatm"
        # --- /ATM ---

        # --- CAN bus (automotive) ---
        "can"
        "can-bcm"
        "can-dev"
        "can-gw"
        "can-isotp"
        "can-raw"
        "can-j1939"
        "can327"
        "c_can"
        "c_can_pci"
        "c_can_platform"
        "ifi_canfd"
        "janz-ican3"
        "m_can"
        "m_can_pci"
        "m_can_platform"
        "phy-can-transceiver"
        "slcan"
        "ucan"
        "vxcan"
        "vcan"
        # --- /CAN bus ---

        # --- Obscure / legacy filesystems ---
        "adfs" # Acorn Disc Filing System
        "affs" # Amiga FFS
        "afs" # Andrew FS
        "befs" # BeOS FS
        "ceph"
        "coda"
        "cramfs"
        "ecryptfs" # Largely superseded by fscrypt / LUKS
        "freevxfs" # Veritas FS
        "gfs2" # Global FS
        "hfs" # Apple HFS
        "hfsplus" # Apple HFS+
        "jffs2" # Journaling Flash FS
        "jfs"
        "kafs" # Kernel AFS
        "minix"
        "nilfs2"
        "ocfs2"
        "orangefs"
        "reiserfs"
        "romfs"
        "sysv"
        "ubifs"
        "ufs"
        "zonefs"
        # --- /Obscure / legacy filesystems ---

        # --- FireWire / IEEE 1394 (DMA attack surface) ---
        "dv1394"
        "firewire-core"
        "firewire-net"
        "firewire-ohci"
        "firewire-sbp2"
        "ohci1394"
        "raw1394"
        "sbp2"
        "video1394"
        # --- /FireWire ---

        # --- GPS / GNSS ---
        "garmin_gps"
        "gnss"
        "gnss-mtk"
        "gnss-serial"
        "gnss-sirf"
        "gnss-ubx"
        "gnss-usb"
        # --- /GPS ---

        # --- Intel Platform Monitoring Telemetry ---
        "pmt_class"
        "pmt_crashlog"
        "pmt_telemetry"
        # --- /Intel PMT ---

        # --- Legacy framebuffer drivers (replaced by DRM/KMS) ---
        "aty128fb"
        "atyfb"
        "cirrusfb"
        "cyber2000fb"
        "cyblafb"
        "gx1fb"
        "hgafb"
        "i810fb"
        "intelfb"
        "kyrofb"
        "lxfb"
        "matroxfb_base"
        "neofb"
        "nvidiafb"
        "pm2fb"
        "radeonfb"
        "rivafb"
        "s1d13xxxfb"
        "savagefb"
        "sisfb"
        "sstfb"
        "tdfxfb"
        "tridentfb"
        "udlfb"
        "vfb"
        "viafb"
        "vt8623fb"
        # --- /Legacy framebuffer drivers ---

        # --- RNDIS (unfixable buffer overflows) ---
        "rndis_host"
        "usb_f_rndis"
        # --- /RNDIS ---

        # --- Replaced / obsolete drivers ---
        "asus_acpi"
        "bcm43xx"
        "brcm80211"
        "de4x5"
        "prism54"
        "amd76x_edac"
        "ath_pci"
        "evbug"
        "snd_aw2"
        "snd_intel8x0m"
        "snd_pcsp"
        "usbkbd" # Legacy boot-protocol HID; usbhid replaces
        "usbmouse" # Legacy boot-protocol HID; usbhid replaces
        # --- /Replaced / obsolete drivers ---

        # --- Misc ---
        "hamradio" # Amateur radio umbrella
        "floppy"
        "vivid" # Test driver, repeated CVE source
        "pcspkr" # PC speaker beep
        # --- /Misc ---
      ];

      environment.etc."modprobe.d/nixos-hardening.conf".text = lib.concatMapStringsSep "\n" (
        mod: "install ${mod} ${pkgs.coreutils}/bin/false"
      ) config.boot.blacklistedKernelModules;

      system.activationScripts.rmmodBlacklisted.text = ''
        for mod in ${
          lib.concatMapStringsSep " " lib.escapeShellArg config.boot.blacklistedKernelModules
        }; do
          if [ -d "/sys/module/''${mod//-/_}" ]; then
            if ! ${pkgs.kmod}/bin/modprobe -r "$mod" 2>/dev/null; then
              echo "warning: failed to unload blacklisted kernel module: $mod" >&2
            fi
          fi
        done
      '';
    })

    (lib.mkIf cfg.minimizeWrappers.enable {
      security.wrappers = {
        su.enable = lib.mkDefault false;
        sudoedit.enable = lib.mkDefault false;
        sg.enable = lib.mkDefault false;
        newgrp.setuid = lib.mkDefault false;
        newuidmap.setuid = lib.mkDefault false;
        newgidmap.setuid = lib.mkDefault false;
        fusermount.enable = lib.mkDefault false;
        fusermount3.enable = lib.mkDefault false;
      } // lib.optionalAttrs config.security.polkit.enable {
        # pkexec wrapper is only defined upstream when polkit is enabled;
        # setting setuid here without a source would fail evaluation.
        pkexec.setuid = lib.mkDefault false;
      };
    })
  ];
}
