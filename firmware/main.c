#include "linker_header.h"
const char *TEXT = "You wrote:\0\0\0\0\0\0";
int read_line_to_buffer(char *buffer)
{
    int buf_count = 0;
    for (;;)
    {
        volatile unsigned long available_data = read_only_bytes_in_uart_queue;
        if (available_data > 0)
        {
            volatile const unsigned long read_data = read_only_uart_queue_next;
            for (int i = 0; i < available_data; i++)
            {
                char read_char = ((char *)&read_data)[i];
                if (read_char > 0)
                {
                    buffer[buf_count] = read_char;
                    buf_count++;
                    if (read_char == '\n')
                    {
                        return buf_count;
                    }
                }
            }
        }
    }
}
void main()
{
    //__asm__ __volatile__("li x10, 2" ::: "x10");
    for (;;)
    {
        char small_buffer[512];
        int count = read_line_to_buffer(small_buffer);
        write_only_to_uart = ((unsigned long *)TEXT)[0];
        write_only_to_uart = ((unsigned long *)TEXT)[1];
        for (int i = 0; i < count; i++)
        {
            char to_write[8] = {0};
            to_write[0] = small_buffer[i];
            write_only_to_uart = *((unsigned long *)to_write);
        }
    }
}

__attribute__((section(".text._start"), naked, noreturn, used)) void _start(void)
{
    __asm__ __volatile__(
        "  la   sp, _stack_pointer\n" // sp = &_stack_pointer
        "  tail main\n"               // tail-call main, never returns
    );
}
