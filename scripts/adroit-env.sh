#=========================================================================
# adroit-env.sh - source this on Princeton's adroit cluster
#=========================================================================
# Sets toolchain paths for the project's build/run scripts to point at
# /home/ECE475/local/encap/* (the ECE 475 staff installs). Usage:
#
#   source scripts/adroit-env.sh
#   ./scripts/run_all_variants.sh
#
# Pinned versions:
#   - riscv-gnu-toolchain-2026.2.13   (riscv64-unknown-elf-gcc 15.2.0,
#                                      supports -march=rv32im_zicsr)
#   - iverilog-v12                    (testbench uses #delays for clock
#                                      and reset; verilator < 5.x lacks
#                                      --timing, hence the iverilog path)
#   - verilator-v5.044                (also available; flip SIM_TOOL to
#                                      verilator if you'd rather)
# To use the lowercase /home/ee475 toolchain (older), unset RISCV_GCC
# before invoking the build scripts — they fall back to whatever is on
# PATH.

ECE475_ROOT=/home/ECE475/local/encap

export RISCV_TOOLCHAIN_DIR="$ECE475_ROOT/riscv-gnu-toolchain-2026.2.13/bin"
export RISCV_GCC="$RISCV_TOOLCHAIN_DIR/riscv64-unknown-elf-gcc"
export RISCV_OBJDUMP="$RISCV_TOOLCHAIN_DIR/riscv64-unknown-elf-objdump"
export RISCV_MARCH=rv32im_zicsr

export PATH="$ECE475_ROOT/iverilog-v12/bin:$ECE475_ROOT/verilator-v5.044/bin:$RISCV_TOOLCHAIN_DIR:$PATH"

# Default sim backend on adroit. iverilog is solid; the verilator 5.044
# binary is also there if you want native C++ speed (set SIM_TOOL=verilator).
export SIM_TOOL=${SIM_TOOL:-iverilog}

echo "[adroit-env] RISCV_GCC=$RISCV_GCC ($($RISCV_GCC --version | head -1))"
echo "[adroit-env] SIM_TOOL=$SIM_TOOL"
