//=========================================================================
// riscv-ooo-commit.S
//=========================================================================
// Test that fails when values commit out of order (I2O2) but passes
// with a proper ROB (I2OI). A mul takes 4 cycles while an add takes 1.
// Without in-order commit, the add overwrites the mul result in the
// register file before the mul completes.

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        //----------------------------------------------------------------
        // Test 1: mul followed by add to same register
        //----------------------------------------------------------------
        // x3 = x1 * x2 (takes 4 cycles in MUL pipe)
        // x3 = x4 + x5 (takes 1 cycle in ALU pipe, finishes first)
        // Without ROB, x3 gets the add result, then mul overwrites it.
        // With ROB, x3 should have the add result (program order).

        li    x1, 7
        li    x2, 6
        li    x4, 100
        li    x5, 200
        mul   x3, x1, x2    // x3 should be 42, but takes 4 cycles
        add   x3, x4, x5    // x3 should be 300, takes 1 cycle
        // In program order, x3 = 300 (the add is last)
        // Without ROB: mul finishes after add, so x3 = 42 (WRONG)
        // With ROB: commits in order, so x3 = 300 (CORRECT)

        TEST_CHECK_EQ( x3, 300 )

        //----------------------------------------------------------------
        // Test 2: Another WAW with mul and add
        //----------------------------------------------------------------
        li    x10, 3
        li    x11, 5
        li    x12, 10
        mul   x6, x10, x11  // x6 = 15 (slow)
        add   x6, x12, x12  // x6 = 20 (fast)
        // Program order: x6 = 20

        TEST_CHECK_EQ( x6, 20 )

        //----------------------------------------------------------------
        // Test 3: Chain where wrong order causes cascading error
        //----------------------------------------------------------------
        li    x10, 4
        li    x11, 5
        li    x12, 1
        mul   x7, x10, x11  // x7 = 20 (slow)
        add   x7, x12, x12  // x7 = 2 (fast, should be final value)
        add   x8, x7, x7    // x8 = x7 + x7 = 4

        TEST_CHECK_EQ( x7, 2 )
        TEST_CHECK_EQ( x8, 4 )

        TEST_RISCV_END
