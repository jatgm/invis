#
# main.py - MicroPython Location Simulation Bridge for Raspberry Pi Pico / Pico W
#
# Deploy this directly onto the Pico's flash drive using Thonny or mpremote.
# Listens for newline-delimited JSON commands over USB Serial (sys.stdin).
#

import sys
import time
import json
import math
import select
from machine import Pin, UART

# Hardware setup
led = Pin("LED", Pin.OUT) if "LED" in dir(Pin) else Pin(25, Pin.OUT)
uart = UART(0, baudrate=9600, tx=Pin(0), rx=Pin(1))

# State
STATE_IDLE = 0
STATE_SPOOFING = 1
STATE_SAFE_HOLD = 2

state = STATE_IDLE
current_lat = 37.334900
current_lon = -122.009020
altitude = 15.0
heading = 0.0
speed_kmh = 0.0
jitter_enabled = False
jitter_radius_m = 1.0

last_packet_time = time.ticks_ms()
last_jitter_time = time.ticks_ms()
last_nmea_time = time.ticks_ms()

FIRMWARE_VERSION = "MicroPython RP2040 v1.3.3"
CABLE_TIMEOUT_MS = 3500

def generate_gaussian(mean=0.0, stddev=1.0):
    """Approximate standard normal using Central Limit Theorem (12 uniforms)."""
    import random
    s = sum(random.random() for _ in range(12)) - 6.0
    return mean + s * stddev

def calculate_nmea_checksum(sentence: str) -> str:
    crc = 0
    clean = sentence.lstrip("$")
    for char in clean:
        crc ^= ord(char)
    return "{:02X}".format(crc)

def emit_nmea():
    if state == STATE_IDLE:
        return

    abs_lat = abs(current_lat)
    lat_deg = int(abs_lat)
    lat_min = (abs_lat - lat_deg) * 60.0
    lat_hemi = "N" if current_lat >= 0 else "S"

    abs_lon = abs(current_lon)
    lon_deg = int(abs_lon)
    lon_min = (abs_lon - lon_deg) * 60.0
    lon_hemi = "E" if current_lon >= 0 else "W"

    speed_knots = (speed_kmh * 1000.0) / 1852.0

    # $GPGGA
    gga_raw = f"GPGGA,120000.00,{lat_deg:02d}{lat_min:07.4f},{lat_hemi},{lon_deg:03d}{lon_min:07.4f},{lon_hemi},1,08,1.0,{altitude:.1f},M,0.0,M,,"
    gga_crc = calculate_nmea_checksum(gga_raw)
    uart.write(f"${gga_raw}*{gga_crc}\r\n")

    # $GPRMC
    rmc_raw = f"GPRMC,120000.00,A,{lat_deg:02d}{lat_min:07.4f},{lat_hemi},{lon_deg:03d}{lon_min:07.4f},{lon_hemi},{speed_knots:.1f},{heading:.1f},010126,,,A"
    rmc_crc = calculate_nmea_checksum(rmc_raw)
    uart.write(f"${rmc_raw}*{rmc_crc}\r\n")

def send_response(data: dict):
    line = json.dumps(data) + "\n"
    sys.stdout.write(line)

def handle_command(line_str: str):
    global state, current_lat, current_lon, altitude, heading, speed_kmh
    global jitter_enabled, jitter_radius_m, last_packet_time

    last_packet_time = time.ticks_ms()
    if state == STATE_SAFE_HOLD:
        state = STATE_SPOOFING

    try:
        cmd_data = json.loads(line_str)
        cmd = cmd_data.get("cmd")

        if cmd == "ping":
            client_ts = cmd_data.get("ts", 0.0)
            send_response({
                "status": "pong",
                "version": FIRMWARE_VERSION,
                "uptime_ms": time.ticks_ms(),
                "state": state,
                "ts": client_ts,
                "lat": current_lat,
                "lon": current_lon
            })
            return

        if cmd == "teleport":
            current_lat = float(cmd_data["lat"])
            current_lon = float(cmd_data["lon"])
            if "alt" in cmd_data:
                altitude = float(cmd_data["alt"])
            if "speed" in cmd_data:
                speed_kmh = float(cmd_data["speed"])
            if "heading" in cmd_data:
                heading = float(cmd_data["heading"])

            state = STATE_SPOOFING
            emit_nmea()
            send_response({"status": "ok", "cmd": "teleport", "lat": current_lat, "lon": current_lon})
            return

        if cmd == "jitter":
            jitter_enabled = bool(cmd_data.get("enabled", False))
            jitter_radius_m = float(cmd_data.get("radius_meters", 1.0))
            send_response({"status": "ok", "cmd": "jitter", "enabled": jitter_enabled, "radius": jitter_radius_m})
            return

        if cmd == "reset":
            state = STATE_IDLE
            speed_kmh = 0.0
            jitter_enabled = False
            send_response({"status": "ok", "cmd": "reset", "msg": "Hardware GPS Restored"})
            return

        if cmd == "route":
            state = STATE_SPOOFING
            send_response({"status": "ok", "cmd": "route", "msg": "Route stream synchronized"})
            return

        if cmd == "route_control":
            send_response({"status": "ok", "cmd": "route_control"})
            return

        send_response({"status": "ignored", "msg": "Unknown command"})

    except Exception as e:
        send_response({"status": "err", "msg": str(e)})

print(f"[{FIRMWARE_VERSION}] Started. Listening on USB CDC...")

# Main Loop
rx_poll = select.poll()
rx_poll.register(sys.stdin, select.POLLIN)

while True:
    now = time.ticks_ms()

    # Check for incoming USB serial lines
    events = rx_poll.poll(5) # 5ms timeout
    if events:
        line = sys.stdin.readline()
        if line and line.strip():
            led.value(1)
            handle_command(line.strip())
            led.value(0)

    # Watchdog failsafe: Anti-Rubberbanding
    if state == STATE_SPOOFING:
        if time.ticks_diff(now, last_packet_time) > CABLE_TIMEOUT_MS:
            state = STATE_SAFE_HOLD
            led.value(1) # Solid on warning

    # Micro-Jitter random walk (~2.5s)
    if state == STATE_SPOOFING and jitter_enabled and speed_kmh < 1.0:
        if time.ticks_diff(now, last_jitter_time) >= 2500:
            last_jitter_time = now
            dy = generate_gaussian(0.0, jitter_radius_m / 2.0)
            dx = generate_gaussian(0.0, jitter_radius_m / 2.0)
            lat_rad = math.radians(current_lat)
            current_lat += (dy / 111139.0)
            current_lon += (dx / (111139.0 * math.cos(lat_rad)))

    # NMEA UART Emission (1Hz)
    if time.ticks_diff(now, last_nmea_time) >= 1000:
        last_nmea_time = now
        emit_nmea()
