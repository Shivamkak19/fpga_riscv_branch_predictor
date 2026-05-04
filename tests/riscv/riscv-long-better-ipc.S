//=========================================================================
// riscv-long-better-ipc.S
//=========================================================================
// Scenario where riscvlong has better IPC than riscvooo. The OoO
// processor has ROB commit overhead: instructions must wait in the ROB
// to commit in order, even though they have completed execution. This
// adds latency. With a tight chain of dependent ALU instructions,
// riscvlong can commit immediately at writeback, while riscvooo must
// wait for in-order commit through the ROB. The scoreboard in the OoO
// processor may also introduce additional stall cycles.

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        //----------------------------------------------------------------
        // Test: Tight dependent ALU chain
        //----------------------------------------------------------------
        // Each instruction depends on the previous. riscvlong bypasses
        // and commits directly. riscvooo has the same bypass paths but
        // the ROB adds commit overhead and the scoreboard may stall
        // more conservatively.

        li    x1, 1
        addi  x1, x1, 1    // x1 = 2
        addi  x1, x1, 1    // x1 = 3
        addi  x1, x1, 1    // x1 = 4
        addi  x1, x1, 1    // x1 = 5
        addi  x1, x1, 1    // x1 = 6
        addi  x1, x1, 1    // x1 = 7
        addi  x1, x1, 1    // x1 = 8
        addi  x1, x1, 1    // x1 = 9
        addi  x1, x1, 1    // x1 = 10
        addi  x1, x1, 1    // x1 = 11
        addi  x1, x1, 1    // x1 = 12
        addi  x1, x1, 1    // x1 = 13
        addi  x1, x1, 1    // x1 = 14
        addi  x1, x1, 1    // x1 = 15
        addi  x1, x1, 1    // x1 = 16
        addi  x1, x1, 1    // x1 = 17
        addi  x1, x1, 1    // x1 = 18
        addi  x1, x1, 1    // x1 = 19
        addi  x1, x1, 1    // x1 = 20
        TEST_CHECK_EQ( x1, 20 )

        TEST_RISCV_END
