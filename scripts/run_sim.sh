#!/usr/bin/env bash
# ==============================================================================
# Script Name : run_sim.sh
# Project     : Modern Computer Architecture - Direct-Mapped Cache Controller
# Author      : Yachna Khanna (M4)
# Email       : yachna.2024@nst.rishihood.edu.in
# Description : Automation script to compile and execute Verilog testbenches
#               using Icarus Verilog (iverilog) and vvp, with optional GTKWave
#               waveform visualization (--wave).
#
# Usage:
#   ./scripts/run_sim.sh [OPTIONS]
#
# Options:
#   --test <name>   Select testbench:
#                     tb_directed   (default: full directed suite TC-01..TC-08)
#                     tb_cache      (golden reference model harness)
#                     tb_smoke      (smoke test)
#                     all           (run all integration testbenches)
#   --wave          Enable VCD dumping (+DUMP) and launch GTKWave if available
#   --clean         Clean the build directory before running
#   --help, -h      Display this help menu
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TEST_TARGET="tb_directed"
OPEN_WAVE=false
CLEAN_BUILD=false

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --test)
            TEST_TARGET="$2"
            shift 2
            ;;
        --wave)
            OPEN_WAVE=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--test <tb_directed|tb_cache|tb_smoke|all>] [--wave] [--clean]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--test <tb_directed|tb_cache|tb_smoke|all>] [--wave] [--clean]"
            exit 1
            ;;
    esac
done

cd "${REPO_ROOT}"

mkdir -p build docs/waveforms

if [ "$CLEAN_BUILD" = true ]; then
    echo "[INFO] Cleaning build directory..."
    rm -rf build/*
fi

# Ensure iverilog and vvp are available in PATH
if ! command -v iverilog &> /dev/null; then
    echo "[ERROR] 'iverilog' command not found in PATH."
    echo "        Please install Icarus Verilog (e.g. via Homebrew: brew install icarus-verilog)"
    exit 127
fi

if ! command -v vvp &> /dev/null; then
    echo "[ERROR] 'vvp' command not found in PATH."
    exit 127
fi

RTL_FILES=(
    rtl/cache_controller.v
    rtl/data_array.v
    rtl/tag_array.v
    rtl/main_memory.v
    rtl/cache_top.v
)

run_single_test() {
    local TB_NAME="$1"
    local TB_FILE="tb/${TB_NAME}.v"
    local SIM_EXE="build/${TB_NAME}"

    if [ ! -f "${TB_FILE}" ]; then
        echo "[ERROR] Testbench file not found: ${TB_FILE}"
        exit 1
    fi

    echo "==============================================================================="
    echo " Compiling ${TB_NAME} with iverilog..."
    echo "==============================================================================="
    iverilog -g2012 -I rtl -o "${SIM_EXE}" "${RTL_FILES[@]}" "${TB_FILE}"

    echo "==============================================================================="
    echo " Running simulation: ${TB_NAME}..."
    echo "==============================================================================="
    local VVP_ARGS=()
    if [ "$OPEN_WAVE" = true ] || [ "$TB_NAME" = "tb_directed" ]; then
        VVP_ARGS+=("+DUMP")
    fi

    vvp "${SIM_EXE}" ${VVP_ARGS[@]+"${VVP_ARGS[@]}"}

    echo "[SUCCESS] Simulation finished for ${TB_NAME}."
}

if [ "$TEST_TARGET" = "all" ]; then
    run_single_test "tb_smoke"
    run_single_test "tb_cache"
    run_single_test "tb_directed"
else
    run_single_test "${TEST_TARGET}"
fi

# Waveform handling
VCD_FILE="docs/waveforms/cache_directed.vcd"
if [ "$OPEN_WAVE" = true ]; then
    if [ -f "${VCD_FILE}" ]; then
        echo "==============================================================================="
        echo " Opening waveform ${VCD_FILE} with GTKWave..."
        echo "==============================================================================="
        if command -v gtkwave &> /dev/null; then
            gtkwave "${VCD_FILE}" &
        else
            echo "[NOTICE] 'gtkwave' is not installed or not in PATH."
            echo "         VCD file generated at: ${VCD_FILE}"
            echo "         To install GTKWave on macOS: brew install --cask gtkwave"
            echo "         Or open ${VCD_FILE} directly in your preferred waveform viewer."
        fi
    else
        echo "[WARNING] Waveform file ${VCD_FILE} not found."
    fi
fi
