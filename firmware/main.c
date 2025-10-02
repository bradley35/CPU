#include "linker_header.h"

void main()
{
    __asm__ __volatile__("li x10, 2" ::: "x10");
    for (;;)
    {
        volatile unsigned long available_data = read_only_bytes_in_uart_queue;
        __asm__ __volatile__("add x10, x10, 1" ::: "x10");

        // Process all available data from the UART queue.
        if (available_data > 0)
        {
            const unsigned long read_data = read_only_uart_queue_next;
            write_only_to_uart = read_data;
            char text[8] = ":)";
            write_only_to_uart = *((unsigned long *)text);
        }
    }
}
__attribute__((naked, noreturn)) void _start(void)
{
    __asm__ __volatile__(
        "  la   sp, _stack_pointer\n" // sp = &_stack_pointer
        "  tail main\n"               // tail-call main, never returns
    );
}
