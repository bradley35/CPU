#pragma once
extern volatile unsigned long read_only_bytes_in_uart_queue;
extern volatile unsigned long read_only_uart_queue_next;
extern volatile unsigned long read_only_bytes_in_uart_write_queue;
extern volatile unsigned long write_only_to_uart;

// From the linker, gives the initial stack pointer
extern void _stack_pointer(void);