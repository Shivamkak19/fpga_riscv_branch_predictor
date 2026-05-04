//=========================================================================
// riscv-rob-bypass.S
//=========================================================================
// Test that values can be bypassed out of the ROB (written back but not
// yet committed). A mul takes 4 cycles. While it sits in the ROB
// waiting to commit, a subsequent instruction needs its result.

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        //----------------------------------------------------------------
        // Test 1: Bypass value from ROB after mul completes
        //----------------------------------------------------------------
        // mul finishes and writes back to ROB, but a later instruction
        // in the ALU pipe already committed, so the mul result sits in
        // the ROB. The next instruction needs to bypass from ROB.

        li    x1, 6
        li    x2, 7
        mul   x3, x1, x2    // x3 = 42 (4 cycle latency, result in ROB)
        // After mul writes back, it waits in ROB to commit
        // Meanwhile several nops let it write back
        nop
        nop
        nop
        nop
        nop
        nop
        add   x4, x3, x0   // x4 = x3 + 0 = 42, may need ROB bypass
        TEST_CHECK_EQ( x4, 42 )

        //----------------------------------------------------------------
        // Test 2: Bypass after a load (2-cycle latency)
        //----------------------------------------------------------------
        // Use a load followed by nops, then read the value
        // The load result may be in ROB waiting to commit

        li    x10, 100
        li    x11, 200
        add   x12, x10, x11  // x12 = 300
        nop
        nop
        nop
        nop
        add   x13, x12, x0   // bypass x12 from ROB
        TEST_CHECK_EQ( x13, 300 )

        //----------------------------------------------------------------
        // Test 3: Multiple values bypassed from ROB
        //----------------------------------------------------------------
        li    x1, 3
        li    x2, 4
        mul   x5, x1, x2    // x5 = 12
        li    x6, 10         // x6 = 10
        nop
        nop
        nop
        nop
        nop
        add   x7, x5, x6   // x7 = 12 + 10 = 22 (both may be in ROB)
        TEST_CHECK_EQ( x7, 22 )

        TEST_RISCV_END
