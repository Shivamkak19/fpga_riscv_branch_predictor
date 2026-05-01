/*======================================================================*/
/* ubmark.ld - Linker script for benchmarks                             */
/*======================================================================*/
/* Places startup at reset_vector (0x80000), then text/data after.      */

OUTPUT_ARCH("riscv:rv32")
ENTRY(_start)

SECTIONS
{
  /* Reserve 4 bytes for an exception handler at 0x4 — unused but kept
     for parity with the lab's test.ld memory map. */
  . = 0x00000004;
  .xcpthandler :
  {
    *(.xcpthandler)
  }

  /* Startup goes at the reset vector. */
  . = 0x00080000;
  .text.init :
  {
    KEEP(*(.text.init))
  }

  /* Then the rest of .text. */
  .text :
  {
    *(.text)
    *(.text.*)
  }

  /* Read-only data immediately after. */
  .rodata :
  {
    *(.rodata)
    *(.rodata.*)
    *(.srodata)
    *(.srodata.*)
  }

  /* Initialized data segment. */
  .data :
  {
    *(.data)
    *(.data.*)
    *(.sdata)
    *(.sdata.*)
  }

  /* BSS — zero-init data. The startup code does not zero this; benchmarks
     that rely on bss being zero must initialize it themselves. The Verilator
     test memory backs this with its $readmemh-loaded array (zeroed by
     default thanks to --x-initial 0), so this is fine in practice. */
  .bss :
  {
    *(.bss)
    *(.bss.*)
    *(.sbss)
    *(.sbss.*)
    *(COMMON)
  }

  _end = .;
}
