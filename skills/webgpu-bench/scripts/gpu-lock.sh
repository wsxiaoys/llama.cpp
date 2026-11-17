#!/usr/bin/env bash
# Serialize a timed GPU command against other webgpu-bench records on this rig.
#
# Two modes:
#   gpu-lock.sh -- <cmd...>          global lock (.gpu-timing.lock), default device
#                                    -> full records and gate/promotion runs (single-lane fidelity)
#   gpu-lock.sh <N> -- <cmd...>      per-device lock (.gpu-timing.lock.<N>) + DRI_PRIME pin to GPU N
#                                    -> --fast records and timing pre-checks (triage; see P001)
#
# P001 (2026-11-17): two lanes on different GPUs run at ~95-98% of solo but with higher variance
# (~6 t/s stddev vs <0.1 solo), so per-GPU lanes are for triage only — gate decisions must come from
# global-lock single-lane records. Non-timing work (builds, `test-backend-ops test`, non-timing
# pre-checks) needs no lock and must not be wrapped.
#
# Wait timeout (seconds) defaults to 7200; override with WEBGPU_LOCK_WAIT.
set -euo pipefail

ROOT=${WEBGPU_BENCH_ROOT:-$HOME/webgpu-bench}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WAIT=${WEBGPU_LOCK_WAIT:-7200}
export WEBGPU_BENCH_LOCKED=1

if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    N=$1; shift
    [ "${1:-}" = "--" ] || { echo "gpu-lock.sh: expected '--' after device index" >&2; exit 2; }
    shift
    [ "$#" -gt 0 ] || { echo "gpu-lock.sh: no command given" >&2; exit 2; }
    LOCK=${WEBGPU_BENCH_LOCK_FILE:-$ROOT/.gpu-timing.lock.$N}
    mkdir -p "$(dirname "$LOCK")"
    exec flock -w "$WAIT" "$LOCK" "$HERE/gpu-pin.sh" "$N" -- "$@"
fi

[ "${1:-}" = "--" ] && shift
[ "$#" -gt 0 ] || { echo "gpu-lock.sh: no command given" >&2; exit 2; }
LOCK=${WEBGPU_BENCH_LOCK_FILE:-$ROOT/.gpu-timing.lock}
mkdir -p "$(dirname "$LOCK")"
exec flock -w "$WAIT" "$LOCK" "$@"
