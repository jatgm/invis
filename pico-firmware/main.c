/*
 * main.c - Raspberry Pi Pico (RP2040) Location Simulation Dongle Firmware
 *
 * Responsibilities:
 * 1. Physical Wired USB CDC-ACM communication with host Swift app.
 * 2. Newline-delimited JSON payload parsing (teleport, route, jitter, reset, ping).
 * 3. Failsafe Anti-Rubberbanding state machine (holds coordinates if cable unplugged).
 * 4. Micro-jitter Gaussian random-walk drift engine.
 * 5. Hardware UART NMEA sentence generator ($GPGGA, $GPRMC) on GP0/GP1.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "pico/stdlib.h"
#include "hardware/uart.h"
#include "hardware/timer.h"
#include "bsp/board.h"
#include "tusb.h"

#define FIRMWARE_VERSION       "RP2040 v1.3.3"
#define UART_ID                uart0
#define BAUD_RATE              9600
#define UART_TX_PIN            0
#define UART_RX_PIN            1
#define LED_PIN                PICO_DEFAULT_LED_PIN

#define USB_RX_BUF_SIZE        1024
#define CABLE_TIMEOUT_MS       3500 // Disconnect failsafe trigger

// Spoofer State Machine
typedef enum {
    STATE_IDLE = 0,
    STATE_SPOOFING,
    STATE_SAFE_HOLD, // Failsafe state on cable unplug
} SpooferState;

typedef struct {
    SpooferState state;
    double current_lat;
    double current_lon;
    double altitude;
    double heading;
    double speed_kmh;

    bool jitter_enabled;
    double jitter_radius_m;

    uint32_t last_packet_time_ms;
    uint32_t last_jitter_time_ms;
    uint32_t last_nmea_time_ms;
} SpooferContext;

static SpooferContext ctx = {
    .state = STATE_IDLE,
    .current_lat = 37.334900,
    .current_lon = -122.009020,
    .altitude = 15.0,
    .heading = 0.0,
    .speed_kmh = 0.0,
    .jitter_enabled = false,
    .jitter_radius_m = 1.0,
    .last_packet_time_ms = 0,
    .last_jitter_time_ms = 0,
    .last_nmea_time_ms = 0,
};

static char rx_line_buffer[USB_RX_BUF_SIZE];
static size_t rx_line_len = 0;

// MARK: - Box-Muller Gaussian PRNG
static double generate_gaussian(double mean, double stddev) {
    double u1 = ((double)rand() + 1.0) / ((double)RAND_MAX + 1.0);
    double u2 = ((double)rand() + 1.0) / ((double)RAND_MAX + 1.0);
    double z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
    return mean + z0 * stddev;
}

// MARK: - NMEA Checksum Calculation
static uint8_t calculate_nmea_checksum(const char* sentence) {
    uint8_t crc = 0;
    // Skip initial '$' if present
    if (*sentence == '$') sentence++;
    while (*sentence && *sentence != '*') {
        crc ^= (uint8_t)(*sentence++);
    }
    return crc;
}

// Emits NMEA $GPGGA and $GPRMC sentences over UART0
static void emit_nmea_sentences(void) {
    if (ctx.state == STATE_IDLE) return;

    double abs_lat = fabs(ctx.current_lat);
    int lat_deg = (int)abs_lat;
    double lat_min = (abs_lat - lat_deg) * 60.0;
    char lat_hemi = (ctx.current_lat >= 0) ? 'N' : 'S';

    double abs_lon = fabs(ctx.current_lon);
    int lon_deg = (int)abs_lon;
    double lon_min = (abs_lon - lon_deg) * 60.0;
    char lon_hemi = (ctx.current_lon >= 0) ? 'E' : 'W';

    double speed_knots = (ctx.speed_kmh * 1000.0) / 1852.0;

    // $GPGGA sentence
    char gga_raw[128];
    snprintf(gga_raw, sizeof(gga_raw),
             "GPGGA,120000.00,%02d%07.4f,%c,%03d%07.4f,%c,1,08,1.0,%.1f,M,0.0,M,,",
             lat_deg, lat_min, lat_hemi, lon_deg, lon_min, lon_hemi, ctx.altitude);
    uint8_t gga_crc = calculate_nmea_checksum(gga_raw);

    char gga_final[140];
    snprintf(gga_final, sizeof(gga_final), "$%s*%02X\r\n", gga_raw, gga_crc);
    uart_puts(UART_ID, gga_final);

    // $GPRMC sentence
    char rmc_raw[128];
    snprintf(rmc_raw, sizeof(rmc_raw),
             "GPRMC,120000.00,A,%02d%07.4f,%c,%03d%07.4f,%c,%.1f,%.1f,010126,,,A",
             lat_deg, lat_min, lat_hemi, lon_deg, lon_min, lon_hemi, speed_knots, ctx.heading);
    uint8_t rmc_crc = calculate_nmea_checksum(rmc_raw);

    char rmc_final[140];
    snprintf(rmc_final, sizeof(rmc_final), "$%s*%02X\r\n", rmc_raw, rmc_crc);
    uart_puts(UART_ID, rmc_final);
}

// MARK: - USB Transmission
static void send_usb_response(const char* json_str) {
    if (tud_cdc_connected()) {
        tud_cdc_write_str(json_str);
        tud_cdc_write_char('\n');
        tud_cdc_write_flush();
    }
}

// MARK: - JSON Command Parser
static void process_incoming_command(char* line) {
    ctx.last_packet_time_ms = to_ms_since_boot(get_absolute_time());

    // If we were in SAFE_HOLD, reconnecting resumes normal operation
    if (ctx.state == STATE_SAFE_HOLD) {
        ctx.state = STATE_SPOOFING;
    }

    // Quick command identification
    if (strstr(line, "\"cmd\":\"ping\"") || strstr(line, "\"cmd\": \"ping\"")) {
        // Extract timestamp if provided
        char* ts_ptr = strstr(line, "\"ts\":");
        double client_ts = 0.0;
        if (ts_ptr) {
            sscanf(ts_ptr + 5, "%lf", &client_ts);
        }

        char resp[180];
        snprintf(resp, sizeof(resp),
                 "{\"status\":\"pong\",\"version\":\"%s\",\"uptime_ms\":%lu,\"state\":%d,\"ts\":%.3f,\"lat\":%.6f,\"lon\":%.6f}",
                 FIRMWARE_VERSION, (unsigned long)ctx.last_packet_time_ms, (int)ctx.state, client_ts, ctx.current_lat, ctx.current_lon);
        send_usb_response(resp);
        return;
    }

    if (strstr(line, "\"cmd\":\"teleport\"") || strstr(line, "\"cmd\": \"teleport\"")) {
        char* lat_ptr = strstr(line, "\"lat\":");
        char* lon_ptr = strstr(line, "\"lon\":");
        char* alt_ptr = strstr(line, "\"alt\":");
        char* spd_ptr = strstr(line, "\"speed\":");
        char* hdg_ptr = strstr(line, "\"heading\":");

        if (lat_ptr && lon_ptr) {
            ctx.current_lat = strtod(lat_ptr + (lat_ptr[5] == ' ' ? 6 : 5), NULL);
            ctx.current_lon = strtod(lon_ptr + (lon_ptr[5] == ' ' ? 6 : 5), NULL);
            if (alt_ptr) ctx.altitude = strtod(alt_ptr + (alt_ptr[5] == ' ' ? 6 : 5), NULL);
            if (spd_ptr) ctx.speed_kmh = strtod(spd_ptr + (spd_ptr[7] == ' ' ? 8 : 7), NULL);
            if (hdg_ptr) ctx.heading = strtod(hdg_ptr + (hdg_ptr[9] == ' ' ? 10 : 9), NULL);

            ctx.state = STATE_SPOOFING;
            emit_nmea_sentences();

            char resp[128];
            snprintf(resp, sizeof(resp), "{\"status\":\"ok\",\"cmd\":\"teleport\",\"lat\":%.6f,\"lon\":%.6f}", ctx.current_lat, ctx.current_lon);
            send_usb_response(resp);
        }
        return;
    }

    if (strstr(line, "\"cmd\":\"jitter\"") || strstr(line, "\"cmd\": \"jitter\"")) {
        char* en_ptr = strstr(line, "\"enabled\":");
        char* rad_ptr = strstr(line, "\"radius_meters\":");

        if (en_ptr) {
            ctx.jitter_enabled = (strstr(en_ptr, "true") != NULL);
        }
        if (rad_ptr) {
            ctx.jitter_radius_m = strtod(rad_ptr + (rad_ptr[15] == ' ' ? 16 : 15), NULL);
        }

        char resp[128];
        snprintf(resp, sizeof(resp), "{\"status\":\"ok\",\"cmd\":\"jitter\",\"enabled\":%s,\"radius\":%.2f}",
                 ctx.jitter_enabled ? "true" : "false", ctx.jitter_radius_m);
        send_usb_response(resp);
        return;
    }

    if (strstr(line, "\"cmd\":\"reset\"") || strstr(line, "\"cmd\": \"reset\"")) {
        ctx.state = STATE_IDLE;
        ctx.speed_kmh = 0.0;
        ctx.jitter_enabled = false;

        send_usb_response("{\"status\":\"ok\",\"cmd\":\"reset\",\"msg\":\"GPS Hardware Failsafe Restored\"}");
        return;
    }

    if (strstr(line, "\"cmd\":\"route\"") || strstr(line, "\"cmd\": \"route\"")) {
        ctx.state = STATE_SPOOFING;
        send_usb_response("{\"status\":\"ok\",\"cmd\":\"route\",\"msg\":\"Route stream synchronized\"}");
        return;
    }

    if (strstr(line, "\"cmd\":\"route_control\"") || strstr(line, "\"cmd\": \"route_control\"")) {
        send_usb_response("{\"status\":\"ok\",\"cmd\":\"route_control\"}");
        return;
    }

    send_usb_response("{\"status\":\"ignored\",\"msg\":\"Unknown command\"}");
}

// Read incoming characters from TinyUSB CDC endpoint
static void cdc_read_task(void) {
    while (tud_cdc_available()) {
        char ch = (char)tud_cdc_read_char();
        if (ch == '\r') continue;

        if (ch == '\n') {
            rx_line_buffer[rx_line_len] = '\0';
            if (rx_line_len > 0) {
                gpio_put(LED_PIN, 1);
                process_incoming_command(rx_line_buffer);
                gpio_put(LED_PIN, 0);
            }
            rx_line_len = 0;
        } else {
            if (rx_line_len < (sizeof(rx_line_buffer) - 1)) {
                rx_line_buffer[rx_line_len++] = ch;
            } else {
                rx_line_len = 0; // Overflow guard
            }
        }
    }
}

// Periodic background tasks (Watchdog failsafe, Micro-jitter, NMEA timer)
static void periodic_tasks(void) {
    uint32_t now = to_ms_since_boot(get_absolute_time());

    // 1. Cable Disconnect Watchdog / Anti-Rubberbanding
    if (ctx.state == STATE_SPOOFING) {
        if ((now - ctx.last_packet_time_ms) > CABLE_TIMEOUT_MS) {
            // Cable severed: Hold last coordinate to prevent abrupt location jumps!
            ctx.state = STATE_SAFE_HOLD;
            gpio_put(LED_PIN, 1); // Solid LED warning
        }
    }

    // 2. Micro-Jitter Drift Loop (~2.5s interval)
    if (ctx.state == STATE_SPOOFING && ctx.jitter_enabled && ctx.speed_kmh < 1.0) {
        if ((now - ctx.last_jitter_time_ms) >= 2500) {
            ctx.last_jitter_time_ms = now;

            // Box-Muller displacement in meters
            double delta_y = generate_gaussian(0.0, ctx.jitter_radius_m / 2.0);
            double delta_x = generate_gaussian(0.0, ctx.jitter_radius_m / 2.0);

            double lat_rad = ctx.current_lat * M_PI / 180.0;
            double meters_per_deg_lon = 111139.0 * cos(lat_rad);

            ctx.current_lat += (delta_y / 111139.0);
            ctx.current_lon += (delta_x / meters_per_deg_lon);
        }
    }

    // 3. Hardware UART NMEA sentence emission (1 Hz)
    if ((now - ctx.last_nmea_time_ms) >= 1000) {
        ctx.last_nmea_time_ms = now;
        emit_nmea_sentences();
    }
}

// MARK: - Main Application
int main(void) {
    board_init();
    tusb_init();

    // Initialize On-board LED
    gpio_init(LED_PIN);
    gpio_set_dir(LED_PIN, GPIO_OUT);
    gpio_put(LED_PIN, 0);

    // Initialize Hardware UART for external NMEA GPS bridge
    uart_init(UART_ID, BAUD_RATE);
    gpio_set_function(UART_TX_PIN, GPIO_FUNC_UART);
    gpio_set_function(UART_RX_PIN, GPIO_FUNC_UART);

    ctx.last_packet_time_ms = to_ms_since_boot(get_absolute_time());
    ctx.last_jitter_time_ms = ctx.last_packet_time_ms;
    ctx.last_nmea_time_ms = ctx.last_packet_time_ms;

    while (1) {
        tud_task();        // TinyUSB device task
        cdc_read_task();   // Parse incoming USB CDC stream
        periodic_tasks();  // Run watchdog and jitter generators
    }

    return 0;
}
