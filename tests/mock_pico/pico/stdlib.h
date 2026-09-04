#pragma once
#include <stdint.h>
#include <stdbool.h>

#define PICO_DEFAULT_LED_PIN 25
#define GPIO_OUT 1
#define GPIO_FUNC_UART 2

typedef uint32_t absolute_time_t;

extern uint32_t mock_simulated_time_ms;
static inline absolute_time_t get_absolute_time(void) { return mock_simulated_time_ms; }
static inline uint32_t to_ms_since_boot(absolute_time_t t) { return t; }

extern int mock_led_value;
static inline void gpio_init(uint32_t pin) {}
static inline void gpio_set_dir(uint32_t pin, bool out) {}
static inline void gpio_put(uint32_t pin, bool val) { if (pin == PICO_DEFAULT_LED_PIN) mock_led_value = val ? 1 : 0; }
static inline void gpio_set_function(uint32_t pin, int fn) {}
