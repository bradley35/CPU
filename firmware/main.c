#include "linker_header.h"

void main()
{
    __asm__ __volatile__("li x10, 2" ::: "x10");
    for (;;)
    {
        // volatile unsigned long available_data = read_only_bytes_in_uart_queue;
        __asm__ __volatile__("add x10, x10, 1" ::: "x10");

        // Process all available data from the UART queue.
        // while (available_data > 0)
        // {
        //     // Read a 64-bit word from the UART queue.
        //     const unsigned long read_data = read_only_uart_queue_next;

        //     // A safe, dependency-free way to add 1 to each byte of the 64-bit value.
        //     const unsigned long val_to_add = 0x0101010101010101;
        //     write_only_to_uart = read_data + val_to_add;

        //     // Update the count for the next iteration.
        //     available_data = read_only_bytes_in_uart_queue;
        // }
    }
}
__attribute__((naked, noreturn)) void _start(void)
{
    __asm__ __volatile__(
        "  la   sp, _stack_pointer\n" // sp = &_stack_pointer
        "  tail main\n"               // tail-call main, never returns
    );
}
