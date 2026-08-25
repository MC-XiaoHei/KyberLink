OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0xE0000000, LENGTH = 8M
    RAM   (rwx) : ORIGIN = 0x80000000, LENGTH = 22K
}

SECTIONS
{
    .text : {
        *(.text._start)
        *(.text*)
        *(.rodata*)
    } > FLASH

    .data : {
        __global_pointer$ = .;
        *(.data*)
    } > RAM

    .bss (NOLOAD) : {
        *(.bss*)
        *(COMMON)
    } > RAM

    . = ALIGN(16);
    . += 2K;
    _stack_top = .;
    _end = .;

    /DISCARD/ : {
        *(.eh_frame*)
        *(.comment*)
        *(.note*)
        *(.riscv.attributes)
    }
}
