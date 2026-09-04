#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

extern char mock_usb_tx_buffer[4096];
extern size_t mock_usb_tx_len;
void mock_usb_clear(void);

static inline void tusb_init(void) {}
static inline void tud_task(void) {}
static inline bool tud_cdc_connected(void) { return true; }
static inline uint32_t tud_cdc_write_str(const char* s) {
    while (*s && mock_usb_tx_len < sizeof(mock_usb_tx_buffer) - 1) {
        mock_usb_tx_buffer[mock_usb_tx_len++] = *s++;
    }
    mock_usb_tx_buffer[mock_usb_tx_len] = '\0';
    return (uint32_t)strlen(s);
}
static inline uint32_t tud_cdc_write_char(char c) {
    if (mock_usb_tx_len < sizeof(mock_usb_tx_buffer) - 1) {
        mock_usb_tx_buffer[mock_usb_tx_len++] = c;
        mock_usb_tx_buffer[mock_usb_tx_len] = '\0';
    }
    return 1;
}
static inline void tud_cdc_write_flush(void) {}
static inline uint32_t tud_cdc_available(void) { return 0; }
static inline int32_t tud_cdc_read_char(void) { return -1; }
