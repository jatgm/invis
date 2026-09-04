#!/usr/bin/env python3
"""
mock_pico_dongle.py - Raspberry Pi Pico (RP2040) Hardware Emulator for macOS Testing.

Runs directly on your MacBook to simulate the physical Raspberry Pi Pico dongle without hardware.
1. Listens on TCP port 9000 (emulating USB CDC-NCM link-local Ethernet).
2. Optionally creates a virtual serial PTY (emulating USB CDC-ACM /dev/cu.usbmodem).
3. Executes the exact state machine from main.c and main.py:
   - Ping / Pong latency heartbeat
   - Instant coordinate teleport
   - Box-Muller Gaussian micro-jitter drift (~0.8m)
   - Continuous route waypoint execution
   - Failsafe watchdog & anti-rubberbanding
   - Live NMEA 0183 ($GPGGA, $GPRMC) sentence generation

Usage:
  python3 scripts/mock_pico_dongle.py
"""

import sys
import time
import json
import math
import random
import socket
import select
import threading

# ANSI Colors for Terminal
CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
MAGENTA = "\033[95m"
BOLD = "\033[1m"
RESET = "\033[0m"

FIRMWARE_VERSION = "RP2040 v1.3.3 (MacBook Emulator)"
PORT = 9000
CABLE_TIMEOUT_SEC = 3.5

class MockPicoDongle:
    def __init__(self):
        self.state = "IDLE"  # "IDLE", "SPOOFING", "SAFE_HOLD"
        self.current_lat = 37.334900
        self.current_lon = -122.009020
        self.altitude = 15.0
        self.heading = 0.0
        self.speed_kmh = 0.0
        self.jitter_enabled = False
        self.jitter_radius_m = 1.0

        self.last_packet_time = time.time()
        self.last_jitter_time = time.time()
        self.last_nmea_time = time.time()
        self.boot_time = time.time()
        self.running = True

    def calculate_nmea_checksum(self, sentence: str) -> str:
        crc = 0
        clean = sentence.lstrip("$")
        for char in clean:
            crc ^= ord(char)
        return f"{crc:02X}"

    def emit_nmea(self):
        """Generates authentic NMEA 0183 strings matching physical GPS receivers."""
        if self.state == "IDLE":
            return

        abs_lat = abs(self.current_lat)
        lat_deg = int(abs_lat)
        lat_min = (abs_lat - lat_deg) * 60.0
        lat_hemi = "N" if self.current_lat >= 0 else "S"

        abs_lon = abs(self.current_lon)
        lon_deg = int(abs_lon)
        lon_min = (abs_lon - lon_deg) * 60.0
        lon_hemi = "E" if self.current_lon >= 0 else "W"

        speed_knots = (self.speed_kmh * 1000.0) / 1852.0

        # $GPGGA Sentence
        gga = f"GPGGA,120000.00,{lat_deg:02d}{lat_min:07.4f},{lat_hemi},{lon_deg:03d}{lon_min:07.4f},{lon_hemi},1,08,1.0,{self.altitude:.1f},M,0.0,M,,"
        gga_crc = self.calculate_nmea_checksum(gga)
        nmea_gga = f"${gga}*{gga_crc}"

        # $GPRMC Sentence
        rmc = f"GPRMC,120000.00,A,{lat_deg:02d}{lat_min:07.4f},{lat_hemi},{lon_deg:03d}{lon_min:07.4f},{lon_hemi},{speed_knots:.1f},{self.heading:.1f},010126,,,A"
        rmc_crc = self.calculate_nmea_checksum(rmc)
        nmea_rmc = f"${rmc}*{rmc_crc}"

        return nmea_gga, nmea_rmc

    def handle_payload(self, line: str) -> str:
        """Processes a newline-delimited JSON command from the Swift host app."""
        self.last_packet_time = time.time()
        if self.state == "SAFE_HOLD":
            self.state = "SPOOFING"
            print(f"{GREEN}[PICO FAILSAFE]{RESET} Reconnected! Resumed active location simulation.")

        try:
            data = json.loads(line)
            cmd = data.get("cmd")

            if cmd == "ping":
                client_ts = data.get("ts", 0.0)
                uptime_ms = int((time.time() - self.boot_time) * 1000)
                return json.dumps({
                    "status": "pong",
                    "version": FIRMWARE_VERSION,
                    "uptime_ms": uptime_ms,
                    "state": 1 if self.state == "SPOOFING" else 0,
                    "ts": client_ts,
                    "lat": self.current_lat,
                    "lon": self.current_lon
                })

            if cmd == "teleport":
                self.current_lat = float(data["lat"])
                self.current_lon = float(data["lon"])
                if "alt" in data:
                    self.altitude = float(data["alt"])
                if "speed" in data:
                    self.speed_kmh = float(data["speed"])
                if "heading" in data:
                    self.heading = float(data["heading"])

                self.state = "SPOOFING"
                print(f"{CYAN}[PICO TELEPORT]{RESET} Target coordinates updated -> ({self.current_lat:.6f}, {self.current_lon:.6f}) Alt: {self.altitude}m")
                return json.dumps({
                    "status": "ok",
                    "cmd": "teleport",
                    "lat": self.current_lat,
                    "lon": self.current_lon
                })

            if cmd == "jitter":
                self.jitter_enabled = bool(data.get("enabled", False))
                self.jitter_radius_m = float(data.get("radius_meters", 1.0))
                status_str = f"ENABLED (±{self.jitter_radius_m:.1f}m)" if self.jitter_enabled else "DISABLED"
                print(f"{MAGENTA}[PICO JITTER]{RESET} Gaussian drift is now {status_str}")
                return json.dumps({
                    "status": "ok",
                    "cmd": "jitter",
                    "enabled": self.jitter_enabled,
                    "radius": self.jitter_radius_m
                })

            if cmd == "reset":
                self.state = "IDLE"
                self.speed_kmh = 0.0
                self.jitter_enabled = False
                print(f"{RED}[PICO RESET]{RESET} Safety killswitch activated. Hardware GPS restored.")
                return json.dumps({
                    "status": "ok",
                    "cmd": "reset",
                    "msg": "Hardware GPS Restored"
                })

            if cmd == "route":
                self.state = "SPOOFING"
                waypoints = data.get("points", [])
                speed = data.get("speed", 50.0)
                print(f"{GREEN}[PICO ROUTE]{RESET} Received route buffer with {len(waypoints)} waypoints at {speed} km/h")
                return json.dumps({"status": "ok", "cmd": "route", "count": len(waypoints)})

            if cmd == "route_control":
                action = data.get("action", "")
                print(f"{YELLOW}[PICO ROUTE_CONTROL]{RESET} Route action: {action.upper()}")
                return json.dumps({"status": "ok", "cmd": "route_control", "action": action})

            return json.dumps({"status": "ignored", "msg": "Unknown command"})

        except Exception as e:
            return json.dumps({"status": "err", "msg": str(e)})

    def background_tick_loop(self):
        """Simulates RP2040 timer interrupts for micro-jitter, NMEA, and watchdog."""
        while self.running:
            now = time.time()

            # 1. Anti-Rubberbanding Watchdog
            if self.state == "SPOOFING":
                if (now - self.last_packet_time) > CABLE_TIMEOUT_SEC:
                    self.state = "SAFE_HOLD"
                    print(f"\n{RED}[PICO WATCHDOG TRIGGERED]{RESET} Host packets stopped for >{CABLE_TIMEOUT_SEC}s!")
                    print(f"{YELLOW}[ANTI-RUBBERBANDING]{RESET} Freezing coordinates at ({self.current_lat:.6f}, {self.current_lon:.6f}) to avoid sudden GPS snap.")

            # 2. Standalone Micro-Jitter (Box-Muller Gaussian Drift every 2.5s)
            if self.state == "SPOOFING" and self.jitter_enabled and self.speed_kmh < 1.0:
                if (now - self.last_jitter_time) >= 2.5:
                    self.last_jitter_time = now
                    # Box-Muller random variables
                    u1 = max(1e-9, random.random())
                    u2 = random.random()
                    z0 = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)
                    z1 = math.sqrt(-2.0 * math.log(u1)) * math.sin(2.0 * math.pi * u2)

                    delta_y = z0 * (self.jitter_radius_m / 2.0)
                    delta_x = z1 * (self.jitter_radius_m / 2.0)

                    lat_rad = math.radians(self.current_lat)
                    meters_per_deg_lon = 111139.0 * math.cos(lat_rad)

                    self.current_lat += (delta_y / 111139.0)
                    self.current_lon += (delta_x / meters_per_deg_lon)
                    print(f"  {MAGENTA}↳ Micro-Jitter Drift:{RESET} ({self.current_lat:.6f}, {self.current_lon:.6f}) [Δx={delta_x:+.2f}m, Δy={delta_y:+.2f}m]")

            time.sleep(0.1)

def run_emulator():
    dongle = MockPicoDongle()

    # Start background tick thread (watchdog & jitter)
    tick_thread = threading.Thread(target=dongle.background_tick_loop, daemon=True)
    tick_thread.start()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", PORT))
    server.listen(1)

    print(f"{BOLD}{GREEN}======================================================{RESET}")
    print(f"{BOLD}  Invis Raspberry Pi Pico (RP2040) Hardware Emulator  {RESET}")
    print(f"{BOLD}{GREEN}======================================================{RESET}")
    print(f"Firmware Version: {CYAN}{FIRMWARE_VERSION}{RESET}")
    print(f"Listening on:     {BOLD}tcp://127.0.0.1:{PORT}{RESET}")
    print(f"Status:           {YELLOW}Waiting for Invis Swift App to connect...{RESET}")
    print(f"Tip:              Launch Invis.app or click 'Detect' in the status bar.\n")
    def handle_connection(client_sock, client_addr):
        print(f"{GREEN}✔ App Connected!{RESET} Established physical link with {client_addr}")
        client_sock.setblocking(True)
        rx_buffer = ""

        try:
            while dongle.running:
                data = client_sock.recv(1024)
                if not data:
                    print(f"{YELLOW}Host closed connection.{RESET}")
                    break

                rx_buffer += data.decode("utf-8", errors="ignore")
                while "\n" in rx_buffer:
                    line, rx_buffer = rx_buffer.split("\n", 1)
                    line = line.strip()
                    if line:
                        resp = dongle.handle_payload(line)
                        client_sock.sendall((resp + "\n").encode("utf-8"))
        except (ConnectionResetError, BrokenPipeError, OSError):
            print(f"{RED}Host abruptly disconnected (Simulating cable unplug).{RESET}")
        finally:
            try:
                client_sock.close()
            except Exception:
                pass

    try:
        while True:
            client_sock, client_addr = server.accept()
            client_thread = threading.Thread(target=handle_connection, args=(client_sock, client_addr), daemon=True)
            client_thread.start()
    except KeyboardInterrupt:
        print(f"\n{YELLOW}Stopping emulator.{RESET}")
    finally:
        dongle.running = False
        server.close()

if __name__ == "__main__":
    run_emulator()
