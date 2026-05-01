//=========================================================================
// startup.S - bare-metal startup for ubmark binaries
//=========================================================================
// Sets up sp at the top of 1MB of test memory, calls main, and on return
// signals PASS via CSR 21. The reset_vector is 0x00080000, so this code
// must be placed there by the linker script.

.section .text.init, "ax"
.align 4
.globl _start
_start:
    // Top-of-memory stack. Memory is 1 MiB, so place sp 16 bytes below the
    // top to leave room for any prologue store. Memory wrap is harmless on
    // the test memory but we stay safely within range.
    li sp, 0x00100000
    addi sp, sp, -16

    // gp = 0 — we build with -mno-relax so the toolchain does not generate
    // gp-relative loads. Setting gp explicitly silences any leftover refs.
    li gp, 0

    // Call main.
    jal ra, main

    // If main returns, signal PASS.
    li t0, 1
    csrw 21, t0

    // Spin so cycles continue until the testbench observes status != 0.
1:  nop
    nop
    nop
    nop
    j 1b
