#!/usr/bin/env bash
# Pin a WebGPU (Dawn/Vulkan) process to one physical NVIDIA GPU.
#
# Mechanism: the Mesa device-select implicit layer (mesa-vulkan-drivers) reorders/filters the
# loader's physical-device list, selecting by PCI address from DRI_PRIME in the form
#   pci-<domain:04x>_<bus:02x>_<dev:02x>_<func:1x>
# A trailing '!' exposes ONLY that device, so Dawn cannot fall back to another GPU.
#
# What does NOT work on the linux-4090 rig (verified, P001):
#   * VK_LOADER_DEVICE_SELECT (libvulkan 1.3.275): present but does not filter physical devices.
#   * MESA_VK_DEVICE_SELECT: parses only <vendor>:<device>, which cannot tell six identical 4090s apart.
#
# Usage:
#   gpu-pin.sh <N> -- <cmd...>    run <cmd> pinned to nvidia-smi index N (0..5)
#   gpu-pin.sh env <N>            print `export DRI_PRIME=...` for eval
set -euo pipefail

resolve() {
    local N=$1 BUSID DOMAIN REST BUS DEVFN DEV FUNC
    BUSID=$(nvidia-smi -i "$N" --query-gpu=pci.bus_id --format=csv,noheader 2>/dev/null | tr -d ' ')
    [ -n "$BUSID" ] || { echo "gpu-pin.sh: no GPU at nvidia-smi index $N" >&2; return 1; }
    DOMAIN=${BUSID%%:*}; REST=${BUSID#*:}
    BUS=${REST%%:*}; DEVFN=${REST#*:}
    DEV=${DEVFN%%.*}; FUNC=${DEVFN#*.}
    DOMAIN=${DOMAIN: -4}
    printf 'pci-%04x_%02x_%02x_%1u' "0x$DOMAIN" "0x$BUS" "0x$DEV" "0x$FUNC"
}

case "${1:-}" in
    env)
        N=${2:-}; [ -n "$N" ] || { echo "usage: gpu-pin.sh env <N>" >&2; exit 2; }
        printf 'export DRI_PRIME=%s!\n' "$(resolve "$N")"
        ;;
    *)
        N=${1:-}; [ -n "$N" ] || { echo "usage: gpu-pin.sh <N> -- <cmd...>" >&2; exit 2; }
        shift
        [ "${1:-}" = "--" ] || { echo "usage: gpu-pin.sh <N> -- <cmd...>" >&2; exit 2; }
        shift
        [ "$#" -gt 0 ] || { echo "usage: gpu-pin.sh <N> -- <cmd...>" >&2; exit 2; }
        export DRI_PRIME="$(resolve "$N")!"
        exec "$@"
        ;;
esac
