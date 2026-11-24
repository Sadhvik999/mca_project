#!/usr/bin/env bash
# Compile and run tb_param_check across all 12 (CACHE_SIZE, BLOCK_SIZE) pairs
# using iverilog -P parameter overrides.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

mkdir -p build results

CACHE_SIZES=(1024 2048 4096 8192)
BLOCK_SIZES=(8 16 32)
PASS_COUNT=0
TOTAL=0

for cs in "${CACHE_SIZES[@]}"; do
    for bs in "${BLOCK_SIZES[@]}"; do
        TOTAL=$((TOTAL + 1))
        vvp_out="build/tb_param_${cs}_${bs}.vvp"
        iverilog -g2012 -Wall -s tb_param_check \
            -P "tb_param_check.CACHE_SIZE=${cs}" \
            -P "tb_param_check.BLOCK_SIZE=${bs}" \
            -o "${vvp_out}" rtl/*.v tb/tb_param_check.v
        vvp "${vvp_out}"
        PASS_COUNT=$((PASS_COUNT + 1))
    done
done

echo "All ${PASS_COUNT}/${TOTAL} parameter configurations passed."
