ENTRY(_start)
PROVIDE(read_only_bytes_in_uart_queue = 0xFFFFFFFFFFFFF000);
PROVIDE(read_only_uart_queue_next = 0xFFFFFFFFFFFFF008);
PROVIDE(read_only_bytes_in_uart_write_queue = 0xFFFFFFFFFFFFF010);
PROVIDE(write_only_to_uart = 0xFFFFFFFFFFFFF018);

/* 4 KiB region. Will be for Bootloader, currently is where all code lives */
MEMORY
{
    BOOT (rxw) : ORIGIN = 0x00000000, LENGTH = 4K
}

/* Set the stack pointer to the end of the BOOT memory region. */
_stack_pointer = ORIGIN(BOOT) + LENGTH(BOOT);

SECTIONS
{
    . = 0x0000000000000000;
    .text : {
        *(.text._start)
        *(.text*)
    } > BOOT

    .data : {
        *(.data*)
        *(.rodata*)
        *(.bss*)
    } > BOOT


}