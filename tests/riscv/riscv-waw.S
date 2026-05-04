//=========================================================================
// riscv-waw.S
//=========================================================================
// WAW (Write-After-Write) scenario that executes correctly on both the
// I2O2 and the finished I2OI processor. This works because the two
// writes are far enough apart that the first completes before the
// second, so they naturally commit in the correct order.

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        //----------------------------------------------------------------
        // Test 1: WAW with enough separation (both correct)
        //----------------------------------------------------------------
        // First write via add (1 cycle), then many nops, then another
        // write to the same register. Since the first write commits
        // before the second even enters the pipeline, no reordering.

        li    x1, 10
        li    x2, 20
        add   x3, x1, x2    // x3 = 30
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        li    x4, 50
        li    x5, 60
        add   x3, x4, x5    // x3 = 110 (well after first write committed)
        TEST_CHECK_EQ( x3, 110 )

        //----------------------------------------------------------------
        // Test 2: WAW with two ALU ops separated by enough distance
        //----------------------------------------------------------------
        li    x10, 5
        add   x6, x10, x10  // x6 = 10
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        li    x11, 99
        add   x6, x11, x0   // x6 = 99
        TEST_CHECK_EQ( x6, 99 )

        //----------------------------------------------------------------
        // Test 3: WAW with mul then add, but enough nops between
        //----------------------------------------------------------------
        // The mul takes 4 cycles. If we wait long enough, the mul
        // result commits before the add writes.
        li    x1, 3
        li    x2, 4
        mul   x7, x1, x2    // x7 = 12
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        li    x8, 77
        add   x7, x8, x0   // x7 = 77 (mul already committed)
        TEST_CHECK_EQ( x7, 77 )

        TEST_RISCV_END
