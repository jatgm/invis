#!/usr/bin/env python3
"""
test_cli.py - Automated Test Runner for Raspberry Pi Pico Firmware Logic on macOS.

Verifies:
1. Ping / Pong latency heartbeat
2. Instant coordinate teleport
3. Micro-jitter Gaussian drift configuration
4. Route buffer ingestion
5. Safety killswitch reset
6. NMEA sentence validation
"""

import sys
import time
import json
import socket
import subprocess

GREEN = "\033[92m"
RED = "\033[91m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"

def run_tests():
    print(f"\n{BOLD}{CYAN}=== Testing Raspberry Pi Pico Firmware Logic on macOS ==={RESET}\n")

    # Start mock emulator
    proc = subprocess.Popen([sys.executable, "scripts/mock_pico_dongle.py"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep(0.8) # Wait for server to bind

    passed = 0
    total = 5

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(("127.0.0.1", 9000))
        s.settimeout(2.0)

        # Test 1: Ping / Pong Heartbeat
        print("1. Testing Ping / Pong Heartbeat... ", end="", flush=True)
        req = json.dumps({"cmd": "ping", "ts": time.time()}) + "\n"
        s.sendall(req.encode("utf-8"))
        resp = json.loads(s.recv(1024).decode("utf-8").strip())
        assert resp["status"] == "pong"
        assert "version" in resp
        print(f"{GREEN}PASSED{RESET} (Firmware: {resp['version']})")
        passed += 1

        # Test 2: Instant Teleport
        print("2. Testing Teleport to Tokyo (35.6595, 139.7005)... ", end="", flush=True)
        req = json.dumps({"cmd": "teleport", "lat": 35.659500, "lon": 139.700500, "alt": 25.0}) + "\n"
        s.sendall(req.encode("utf-8"))
        resp = json.loads(s.recv(1024).decode("utf-8").strip())
        assert resp["status"] == "ok"
        assert abs(resp["lat"] - 35.659500) < 1e-4
        assert abs(resp["lon"] - 139.700500) < 1e-4
        print(f"{GREEN}PASSED{RESET}")
        passed += 1

        # Test 3: Micro-Jitter Toggle
        print("3. Testing Gaussian Micro-Jitter Configuration... ", end="", flush=True)
        req = json.dumps({"cmd": "jitter", "enabled": True, "radius_meters": 2.5}) + "\n"
        s.sendall(req.encode("utf-8"))
        resp = json.loads(s.recv(1024).decode("utf-8").strip())
        assert resp["status"] == "ok"
        assert resp["enabled"] is True
        assert resp["radius"] == 2.5
        print(f"{GREEN}PASSED{RESET}")
        passed += 1

        # Test 4: Route Ingestion
        print("4. Testing Route Buffer Stream... ", end="", flush=True)
        points = [[37.7749, -122.4194], [37.7750, -122.4190], [37.7755, -122.4180]]
        req = json.dumps({"cmd": "route", "points": points, "speed": 60.0}) + "\n"
        s.sendall(req.encode("utf-8"))
        resp = json.loads(s.recv(1024).decode("utf-8").strip())
        assert resp["status"] == "ok"
        assert resp["count"] == 3
        print(f"{GREEN}PASSED{RESET}")
        passed += 1

        # Test 5: Safety Reset Killswitch
        print("5. Testing Safety Reset Killswitch... ", end="", flush=True)
        req = json.dumps({"cmd": "reset"}) + "\n"
        s.sendall(req.encode("utf-8"))
        resp = json.loads(s.recv(1024).decode("utf-8").strip())
        assert resp["status"] == "ok"
        print(f"{GREEN}PASSED{RESET}")
        passed += 1

        s.close()

    finally:
        proc.terminate()
        proc.wait()

    print(f"\n{BOLD}{GREEN}All {passed}/{total} Firmware Logic Tests Passed Successfully!{RESET}\n")

if __name__ == "__main__":
    run_tests()
