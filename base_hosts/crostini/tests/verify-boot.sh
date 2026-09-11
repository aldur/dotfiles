#!/usr/bin/env bash
# A complete probe log cannot excuse a VM timeout or failed shutdown.
set -euo pipefail
vm_status=${1:?VM exit status required}
probe_log=${2:?Probe log required}
check_probes=${3:?Probe checker required}
kernel_release=${4:?Kernel release file or - required}
image_size=${5:?Original image size required}

if [ "$vm_status" -ne 0 ]; then
  echo "FAIL: crosvm exited with status $vm_status" >&2
  exit 1
fi
"$check_probes" "$probe_log"

# The no-session negative control exits before application/resize probes.
if [ "$kernel_release" = - ]; then
  exit 0
fi
tr -d '\r' < "$probe_log" | grep -Fx "PROBE kernel $(cat "$kernel_release")" > /dev/null
root_size=$(tr -d '\r' < "$probe_log" | sed -n 's/^PROBE root btrfs *\([0-9]*\).*$/\1/p')
if [[ ! "$root_size" =~ ^[0-9]+$ ]] || [ "$root_size" -le "$image_size" ]; then
  echo "FAIL: root filesystem was not grown" >&2
  exit 1
fi
