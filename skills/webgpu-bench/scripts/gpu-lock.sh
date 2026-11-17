#!/usr/bin/env bash
# Serialize a timed GPU command against other webgpu-bench records on this rig.
#
# Every record shares one unpinned WebGPU device, so e2e/ops/profile timing must run one at a time.
# Non-timing work (builds, `test-backend-ops test`, non-timing pre-checks) is safe to overlap and
# must NOT be wrapped.
#
# Usage: gpu-lock.sh <command> [args...]
#   gpu-lock.sh skills/webgpu-bench/scripts/run.sh --tag E00N-<slug> --fast
#   gpu-lock.sh build/bin/test-backend-ops perf -b WebGPU -o MUL_MAT -p '<params>'
#
# Wait timeout (seconds) defaults to 7200; override with WEBGPU_LOCK_WAIT.
set -euo pipefail

ROOT=${WEBGPU_BENCH_ROOT:-$HOME/webgpu-bench}
LOCK=${WEBGPU_BENCH_LOCK_FILE:-$ROOT/.gpu-timing.lock}
mkdir -p "$(dirname "$LOCK")"
export WEBGPU_BENCH_LOCKED=1
exec flock -w "${WEBGPU_LOCK_WAIT:-7200}" "$LOCK" "$@"
