#!/bin/bash
# Run an MagentaRT executable (mrt-cli / mrt-play) from the CLI.
#
# MLX finds `mlx.metallib` next to the running binary (dladdr-based colocated
# lookup; for a statically-linked MLX that resolves to the executable's dir).
# `swift build` doesn't place it there, so this script copies the metallib from
# Frameworks/ next to the built binary before exec'ing it.
#
# Usage: scripts/run.sh <mrt-cli|mrt-play> [args…]
#        scripts/run.sh mrt-cli --model <mlxfn> --prompt "disco funk" --out out.wav
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT="${1:?usage: run.sh <mrt-cli|mrt-play> [args…]}"
shift || true

# Release by default: the offline generate loop is ~15× faster than debug
# (≈9 ms/frame vs ≈140 ms/frame for mrt2_small). Override with CONFIG=debug.
CONFIG="${CONFIG:-release}"
METALLIB="${ROOT}/Frameworks/mlx.metallib"
[ -f "${METALLIB}" ] || { echo "missing ${METALLIB} — build the xcframework first" >&2; exit 1; }

swift build --product "${PRODUCT}" -c "${CONFIG}" >&2
BINDIR="$(swift build --product "${PRODUCT}" -c "${CONFIG}" --show-bin-path)"
cp -f "${METALLIB}" "${BINDIR}/mlx.metallib"

exec "${BINDIR}/${PRODUCT}" "$@"
