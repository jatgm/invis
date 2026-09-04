#!/usr/bin/env python3
"""
test_pico_micropython.py - Automated Unit Test Suite for Raspberry Pi Pico MicroPython Firmware.

Directly imports and tests `pico-firmware/micropython/main.py` in a simulated
RP2040 hardware environment with mock `machine.Pin`, `machine.UART`, and MicroPython `time` ticks.
"""

import sys
import os
import types
import math
import json
import unittest

# Setup path
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIRMWARE_DIR = os.path.join(REPO_ROOT, "pico-firmware", "micropython")
sys.path.insert(0, FIRMWARE_DIR)

# --- Mock MicroPython Hardware Environment ---
class MockPin:
    OUT = 1
    IN = 0
    def __init__(self, id, mode=-1, value=0):
        self.id = id
        self.mode = mode
        self._val = value

    def value(self, val=None):
        if val is not None:
            self._val = val
        return self._val

class MockUART:
    def __init__(self, id, baudrate=9600, tx=None, rx=None):
        self.id = id
        self.baudrate = baudrate
        self.tx = tx
        self.rx = rx
        self.buffer = bytearray()

    def write(self, data):
        if isinstance(data, str):
            data = data.encode("utf-8")
        self.buffer.extend(data)
        return len(data)

    def read_sentences(self):
        content = self.buffer.decode("utf-8", errors="ignore")
        self.buffer.clear()
        return [line.strip() for line in content.split("\r\n") if line.strip()]

# Mock machine module
mock_machine = types.ModuleType("machine")
mock_machine.Pin = MockPin
mock_machine.UART = MockUART
sys.modules["machine"] = mock_machine

# Mock MicroPython time methods
import time
virtual_time_ms = 10000

def mock_ticks_ms():
    global virtual_time_ms
    return virtual_time_ms

def mock_ticks_diff(t1, t2):
    return t1 - t2

def mock_ticks_add(t, delta):
    return t + delta

time.ticks_ms = mock_ticks_ms
time.ticks_diff = mock_ticks_diff
time.ticks_add = mock_ticks_add

# Now import the actual firmware script
import main as pico_firmware


class TestPicoMicroPythonFirmware(unittest.TestCase):
    def setUp(self):
        global virtual_time_ms
        virtual_time_ms = 10000
        pico_firmware.state = pico_firmware.STATE_IDLE
        pico_firmware.current_lat = 37.334900
        pico_firmware.current_lon = -122.009020
        pico_firmware.altitude = 15.0
        pico_firmware.heading = 0.0
        pico_firmware.speed_kmh = 0.0
        pico_firmware.jitter_enabled = False
        pico_firmware.jitter_radius_m = 1.0
        pico_firmware.last_packet_time = virtual_time_ms
        pico_firmware.last_jitter_time = virtual_time_ms
        pico_firmware.last_nmea_time = virtual_time_ms
        pico_firmware.uart.buffer.clear()
        self.responses = []

        # Intercept send_response
        pico_firmware.send_response = lambda data: self.responses.append(data)

    def test_01_ping_pong(self):
        """Verify ping command returns pong with firmware version and state."""
        cmd = json.dumps({"cmd": "ping", "ts": 123456.789})
        pico_firmware.handle_command(cmd)

        self.assertEqual(len(self.responses), 1)
        resp = self.responses[0]
        self.assertEqual(resp["status"], "pong")
        self.assertIn("RP2040", resp["version"])
        self.assertEqual(resp["ts"], 123456.789)
        self.assertEqual(resp["state"], pico_firmware.STATE_IDLE)
        self.assertAlmostEqual(resp["lat"], 37.334900, places=5)
        self.assertAlmostEqual(resp["lon"], -122.009020, places=5)

    def test_02_teleport_command(self):
        """Verify teleport command updates coordinates, altitude, speed, heading, and state."""
        cmd = json.dumps({
            "cmd": "teleport",
            "lat": 35.659500,
            "lon": 139.700500,
            "alt": 42.0,
            "speed": 60.0,
            "heading": 180.5
        })
        pico_firmware.handle_command(cmd)

        self.assertEqual(pico_firmware.state, pico_firmware.STATE_SPOOFING)
        self.assertAlmostEqual(pico_firmware.current_lat, 35.659500, places=5)
        self.assertAlmostEqual(pico_firmware.current_lon, 139.700500, places=5)
        self.assertAlmostEqual(pico_firmware.altitude, 42.0, places=1)
        self.assertAlmostEqual(pico_firmware.speed_kmh, 60.0, places=1)
        self.assertAlmostEqual(pico_firmware.heading, 180.5, places=1)

        self.assertEqual(len(self.responses), 1)
        self.assertEqual(self.responses[0]["status"], "ok")
        self.assertEqual(self.responses[0]["cmd"], "teleport")

    def test_03_nmea_sentence_emission_and_checksums(self):
        """Verify NMEA $GPGGA and $GPRMC sentences formatting and valid CRC."""
        pico_firmware.state = pico_firmware.STATE_SPOOFING
        pico_firmware.current_lat = 37.774900
        pico_firmware.current_lon = -122.419400
        pico_firmware.altitude = 20.0
        pico_firmware.speed_kmh = 36.0 # ~19.4 knots
        pico_firmware.heading = 90.0

        pico_firmware.emit_nmea()
        sentences = pico_firmware.uart.read_sentences()
        self.assertEqual(len(sentences), 2)

        gga = sentences[0]
        rmc = sentences[1]

        # Verify format & checksums
        self.assertTrue(gga.startswith("$GPGGA,"))
        self.assertTrue(rmc.startswith("$GPRMC,"))

        for s in [gga, rmc]:
            self.assertIn("*", s)
            body, crc = s[1:].split("*")
            expected_crc = pico_firmware.calculate_nmea_checksum(body)
            self.assertEqual(crc, expected_crc, f"Checksum mismatch for {s}")

        # Verify latitude / longitude formatting: 37 deg 46.4940 min N, 122 deg 25.1640 min W
        self.assertIn(",3746.4940,N,", gga)
        self.assertIn(",12225.1640,W,", gga)

    def test_04_micro_jitter_configuration_and_drift(self):
        """Verify micro-jitter configuration and random-walk coordinate drift."""
        cmd = json.dumps({"cmd": "jitter", "enabled": True, "radius_meters": 3.0})
        pico_firmware.handle_command(cmd)

        self.assertTrue(pico_firmware.jitter_enabled)
        self.assertAlmostEqual(pico_firmware.jitter_radius_m, 3.0)

        # Set to spoofing and stationary (speed < 1.0 km/h)
        pico_firmware.state = pico_firmware.STATE_SPOOFING
        pico_firmware.speed_kmh = 0.0
        init_lat = pico_firmware.current_lat
        init_lon = pico_firmware.current_lon

        global virtual_time_ms
        virtual_time_ms += 3000 # Advance by 3 seconds (>2500ms interval)
        pico_firmware.tick(virtual_time_ms)

        # Coordinate should have drifted slightly within Gaussian radius
        drift_lat_m = abs(pico_firmware.current_lat - init_lat) * 111139.0
        drift_lon_m = abs(pico_firmware.current_lon - init_lon) * 111139.0 * math.cos(math.radians(init_lat))
        total_drift = math.hypot(drift_lat_m, drift_lon_m)
        self.assertGreater(total_drift, 0.0)
        self.assertLess(total_drift, 15.0) # Reasonable bound for Gaussian samples

    def test_05_anti_rubberbanding_watchdog(self):
        """Verify watchdog transitions to STATE_SAFE_HOLD after cable disconnect timeout."""
        global virtual_time_ms
        pico_firmware.state = pico_firmware.STATE_SPOOFING
        pico_firmware.last_packet_time = virtual_time_ms

        # Advance time by 3000ms (below 3500ms threshold)
        virtual_time_ms += 3000
        pico_firmware.tick(virtual_time_ms)
        self.assertEqual(pico_firmware.state, pico_firmware.STATE_SPOOFING)

        # Advance time past 3500ms threshold (simulate cable unplug)
        virtual_time_ms += 600
        pico_firmware.tick(virtual_time_ms)

        # Firmware should now freeze coordinates in SAFE_HOLD and turn LED solid ON
        self.assertEqual(pico_firmware.state, pico_firmware.STATE_SAFE_HOLD)
        self.assertEqual(pico_firmware.led.value(), 1)

    def test_06_reconnect_resumption_from_safe_hold(self):
        """Verify receiving a new packet automatically recovers from SAFE_HOLD to SPOOFING."""
        pico_firmware.state = pico_firmware.STATE_SAFE_HOLD

        cmd = json.dumps({"cmd": "ping", "ts": 999.0})
        pico_firmware.handle_command(cmd)

        self.assertEqual(pico_firmware.state, pico_firmware.STATE_SPOOFING)

    def test_07_safety_killswitch_reset(self):
        """Verify reset command restores STATE_IDLE and disables active spoofing."""
        pico_firmware.state = pico_firmware.STATE_SPOOFING
        pico_firmware.jitter_enabled = True

        cmd = json.dumps({"cmd": "reset"})
        pico_firmware.handle_command(cmd)

        self.assertEqual(pico_firmware.state, pico_firmware.STATE_IDLE)
        self.assertFalse(pico_firmware.jitter_enabled)
        self.assertEqual(self.responses[0]["status"], "ok")
        self.assertEqual(self.responses[0]["cmd"], "reset")

        # In STATE_IDLE, emit_nmea should be silent
        pico_firmware.uart.buffer.clear()
        pico_firmware.emit_nmea()
        sentences = pico_firmware.uart.read_sentences()
        self.assertEqual(len(sentences), 0)


if __name__ == "__main__":
    unittest.main()
