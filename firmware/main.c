#include "linker_header.h"
void _start()
{
    for (;;)
    {
        unsigned long available_data = read_only_bytes_in_uart_queue;
        if (available_data > 0)
        {
            // Read from the data and write back + 1;
            unsigned long read_data = read_only_uart_queue_next;
            unsigned char to_write[8];
            for (int i = 0; i < 8; i++)
            {
                to_write[i] = ((char *)&read_data)[i] + 1;
            }
            write_only_to_uart = *((unsigned long *)&to_write);
        }
        // asm("add x10, x0, 1;"
        //     "add x11, x10, x10;");
    }
}