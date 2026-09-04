#pragma once
#include <stdint.h>
#include <stddef.h>

typedef void* uart_inst_t;
#define uart0 ((uart_inst_t)0)

extern char mock_uart_buffer[4096];
extern size_t mock_uart_len;
void mock_uart_clear(void);

static inline void uart_init(uart_inst_t u, uint32_t baud) {}
static inline void uart_puts(uart_inst_t u, const char* s) {
    while (*s && mock_uart_len < sizeof(mock_uart_buffer) - 1) {
        mock_uart_buffer[mock_uart_len++] = *s++;
    }
    mock_uart_buffer[mock_uart_len] = '\0';
}
