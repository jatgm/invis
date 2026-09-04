/*
 * test_pico_c.c - Native Automated Unit Test Suite for Raspberry Pi Pico C Firmware (main.c).
 *
 * Compiles and executes directly on macOS with clang to test:
 * 1. JSON command parsing (ping, teleport, jitter, route, reset)
 * 2. Hardware UART NMEA sentence generation ($GPGGA, $GPRMC) & checksum algorithms
 * 3. Failsafe Watchdog & Anti-Rubberbanding state machine (STATE_SAFE_HOLD)
 * 4. Micro-jitter Gaussian drift engine
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <assert.h>

// Mock variables referenced in mock headers
uint32_t mock_simulated_time_ms = 10000;
int mock_led_value = 0;
char mock_uart_buffer[4096] = {0};
size_t mock_uart_len = 0;
char mock_usb_tx_buffer[4096] = {0};
size_t mock_usb_tx_len = 0;

void mock_uart_clear(void) {
    mock_uart_buffer[0] = '\0';
    mock_uart_len = 0;
}

void mock_usb_clear(void) {
    mock_usb_tx_buffer[0] = '\0';
    mock_usb_tx_len = 0;
}

// Rename main in main.c so we can provide our test runner main
#define main pico_firmware_main
#include "../pico-firmware/main.c"
#undef main

#define GREEN "\033[92m"
#define RED   "\033[91m"
#define CYAN  "\033[96m"
#define BOLD  "\033[1m"
#define RESET "\033[0m"

static int tests_passed = 0;
static int total_tests = 0;

#define TEST_ASSERT(expr, msg) do { \
    if (!(expr)) { \
        printf("%sFAILED%s\n  Assertion failed: %s (%s:%d)\n", RED, RESET, msg, __FILE__, __LINE__); \
        exit(1); \
    } \
} while(0)

static void test_ping_pong(void) {
    total_tests++;
    printf("1. Testing C Firmware Ping / Pong... ");
    mock_usb_clear();

    char cmd[] = "{\"cmd\":\"ping\",\"ts\":1710000.123}";
    process_incoming_command(cmd);

    TEST_ASSERT(strstr(mock_usb_tx_buffer, "\"status\":\"pong\"") != NULL, "Pong status missing");
    TEST_ASSERT(strstr(mock_usb_tx_buffer, "RP2040") != NULL, "Firmware version missing");
    TEST_ASSERT(strstr(mock_usb_tx_buffer, "1710000.123") != NULL, "Client timestamp missing or corrupted");

    printf("%sPASSED%s\n", GREEN, RESET);
    tests_passed++;
}

static void test_teleport_compact_and_spaced(void) {
    total_tests++;
    printf("2. Testing C Firmware Teleport Command Parsing... ");
    mock_usb_clear();
    mock_uart_clear();

    // Test compact JSON format
    char cmd1[] = "{\"cmd\":\"teleport\",\"lat\":35.659500,\"lon\":139.700500,\"alt\":32.5,\"speed\":65.0,\"heading\":180.2}";
    process_incoming_command(cmd1);

    TEST_ASSERT(ctx.state == STATE_SPOOFING, "State should be STATE_SPOOFING");
    TEST_ASSERT(fabs(ctx.current_lat - 35.659500) < 1e-4, "Latitude mismatch in compact JSON");
    TEST_ASSERT(fabs(ctx.current_lon - 139.700500) < 1e-4, "Longitude mismatch in compact JSON");
    TEST_ASSERT(fabs(ctx.altitude - 32.5) < 1e-2, "Altitude mismatch in compact JSON");
    TEST_ASSERT(fabs(ctx.speed_kmh - 65.0) < 1e-2, "Speed mismatch in compact JSON");
    TEST_ASSERT(fabs(ctx.heading - 180.2) < 1e-2, "Heading mismatch in compact JSON");

    // Test spaced JSON format
    char cmd2[] = "{\"cmd\": \"teleport\", \"lat\": 48.858400, \"lon\": 2.294500}";
    process_incoming_command(cmd2);

    TEST_ASSERT(fabs(ctx.current_lat - 48.858400) < 1e-4, "Latitude mismatch in spaced JSON");
    TEST_ASSERT(fabs(ctx.current_lon - 2.294500) < 1e-4, "Longitude mismatch in spaced JSON");

    printf("%sPASSED%s\n", GREEN, RESET);
    tests_passed++;
}

static void test_nmea_sentences_and_checksums(void) {
    total_tests++;
    printf("3. Testing C Firmware NMEA Emission & Checksums... ");
    mock_uart_clear();

    ctx.state = STATE_SPOOFING;
    ctx.current_lat = 37.774900;
    ctx.current_lon = -122.419400;
    ctx.altitude = 18.0;
    ctx.speed_kmh = 36.0;
    ctx.heading = 90.0;

    emit_nmea_sentences();

    TEST_ASSERT(strstr(mock_uart_buffer, "$GPGGA,") != NULL, "$GPGGA sentence missing");
    TEST_ASSERT(strstr(mock_uart_buffer, "$GPRMC,") != NULL, "$GPRMC sentence missing");
    // Verify coordinates in DDMM.MMMM format: 3746.4940,N and 12225.1640,W
    TEST_ASSERT(strstr(mock_uart_buffer, "3746.4940,N") != NULL, "Latitude NMEA format incorrect");
    TEST_ASSERT(strstr(mock_uart_buffer, "12225.1640,W") != NULL, "Longitude NMEA format incorrect");

    // Validate checksum algorithm matches expected NMEA standard
    char* gga_start = strstr(mock_uart_buffer, "$GPGGA");
    char* gga_end = strstr(gga_start, "\r\n");
    char gga_line[140] = {0};
    strncpy(gga_line, gga_start, gga_end - gga_start);

    char* star = strchr(gga_line, '*');
    TEST_ASSERT(star != NULL, "Asterisk missing in NMEA sentence");
    *star = '\0';
    uint8_t expected_crc = calculate_nmea_checksum(gga_line);
    uint8_t sentence_crc = (uint8_t)strtol(star + 1, NULL, 16);
    TEST_ASSERT(expected_crc == sentence_crc, "NMEA checksum mismatch");

    printf("%sPASSED%s\n", GREEN, RESET);
    tests_passed++;
}

static void test_micro_jitter_drift(void) {
    total_tests++;
    printf("4. Testing C Firmware Gaussian Micro-Jitter... ");

    char cmd[] = "{\"cmd\":\"jitter\",\"enabled\":true,\"radius_meters\":2.5}";
    process_incoming_command(cmd);

    TEST_ASSERT(ctx.jitter_enabled == true, "Jitter should be enabled");
    TEST_ASSERT(fabs(ctx.jitter_radius_m - 2.5) < 1e-2, "Jitter radius mismatch");

    ctx.state = STATE_SPOOFING;
    ctx.speed_kmh = 0.0;
    double start_lat = ctx.current_lat;
    double start_lon = ctx.current_lon;

    // Advance time by 3000ms (>2500ms jitter tick)
    mock_simulated_time_ms += 3000;
    periodic_tasks();

    double drift_lat_m = fabs(ctx.current_lat - start_lat) * 111139.0;
    double drift_lon_m = fabs(ctx.current_lon - start_lon) * 111139.0 * cos(start_lat * M_PI / 180.0);
    double total_drift = hypot(drift_lat_m, drift_lon_m);

    TEST_ASSERT(total_drift > 0.0, "Coordinates should drift when jitter is active");
    TEST_ASSERT(total_drift < 15.0, "Drift exceeded realistic bounds");

    printf("%sPASSED%s\n", GREEN, RESET);
    tests_passed++;
}

static void test_watchdog_anti_rubberbanding(void) {
    total_tests++;
    printf("5. Testing C Firmware Watchdog & Anti-Rubberbanding... ");

    ctx.state = STATE_SPOOFING;
    ctx.last_packet_time_ms = mock_simulated_time_ms;
    mock_led_value = 0;

    // Advance time within tolerance
    mock_simulated_time_ms += 3000;
    periodic_tasks();
    TEST_ASSERT(ctx.state == STATE_SPOOFING, "State should remain SPOOFING before timeout");

    // Advance time past 3500ms timeout
    mock_simulated_time_ms += 600;
    periodic_tasks();

    TEST_ASSERT(ctx.state == STATE_SAFE_HOLD, "State should transition to STATE_SAFE_HOLD on timeout");
    TEST_ASSERT(mock_led_value == 1, "LED must turn solid ON during SAFE_HOLD failsafe");

    // Reconnecting resumes SPOOFING
    char ping_cmd[] = "{\"cmd\":\"ping\"}";
    process_incoming_command(ping_cmd);
    TEST_ASSERT(ctx.state == STATE_SPOOFING, "State should resume to STATE_SPOOFING on packet RX");

    printf("%sPASSED%s\n", GREEN, RESET);
    tests_passed++;
}

static void test_safety_killswitch(void) {
    total_tests++;
    printf("6. Testing C Firmware Safety Killswitch... ");
    mock_uart_clear();

    char cmd[] = "{\"cmd\":\"reset\"}";
    process_incoming_command(cmd);

    TEST_ASSERT(ctx.state == STATE_IDLE, "State must be STATE_IDLE after reset");
    TEST_ASSERT(ctx.jitter_enabled == false, "Jitter must be disabled after reset");

    // Verify NMEA emission ceases in STATE_IDLE
    emit_nmea_sentences();
    TEST_ASSERT(mock_uart_len == 0, "UART should be silent in STATE_IDLE");

    printf("%sPASSED%s\n", GREEN, RESET);
    tests_passed++;
}

int main(void) {
    printf("\n%s%s=== Running Native Unit Tests for Raspberry Pi Pico C Firmware (main.c) ===%s\n\n", BOLD, CYAN, RESET);

    test_ping_pong();
    test_teleport_compact_and_spaced();
    test_nmea_sentences_and_checksums();
    test_micro_jitter_drift();
    test_watchdog_anti_rubberbanding();
    test_safety_killswitch();

    printf("\n%s%sAll %d/%d C Firmware Unit Tests Passed Successfully!%s\n\n", BOLD, GREEN, tests_passed, total_tests, RESET);
    return 0;
}
