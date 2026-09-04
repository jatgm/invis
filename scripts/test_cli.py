#!/usr/bin/env python3
"""
test_cli.py - Master Automated Test Runner for Raspberry Pi Pico Firmware on macOS.

Verifies:
1. MicroPython firmware (`pico-firmware/micropython/main.py`)
2. C firmware (`pico-firmware/main.c`) compiled with clang
3. End-to-end Socket & Protocol Integration (`scripts/mock_pico_dongle.py`)
"""

import sys
import os
import time
import json
import socket
import subprocess

GREEN = "\033[92m"
RED = "\033[91m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def run_micropython_tests():
    res = subprocess.run([sys.executable, os.path.join(REPO_ROOT, "tests", "test_pico_micropython.py")])
    if res.returncode != 0:
        print(f"{RED}MicroPython firmware tests failed!{RESET}")
        sys.exit(1)

def run_c_firmware_tests():
    test_src = os.path.join(REPO_ROOT, "tests", "test_pico_c.c")
    test_bin = os.path.join(REPO_ROOT, "tests", "test_pico_c")
    include_dir = os.path.join(REPO_ROOT, "tests", "mock_pico")

    compile_res = subprocess.run([
        "clang", "-O2", f"-I{include_dir}", test_src, "-o", test_bin
    ])
    if compile_res.returncode != 0:
        print(f"{RED}Failed to compile C firmware tests!{RESET}")
        sys.exit(1)

    run_res = subprocess.run([test_bin])
    if run_res.returncode != 0:
        print(f"{RED}C firmware unit tests failed!{RESET}")
        sys.exit(1)

def run_integration_tests():
    # Start mock emulator
    proc = subprocess.Popen([sys.executable, os.path.join(REPO_ROOT, "scripts", "mock_pico_dongle.py")],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
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

    print(f"\n{BOLD}{GREEN}All {passed}/{total} Integration Tests Passed Successfully!{RESET}")

def main():
    print(f"\n{BOLD}{GREEN}=================================================================={RESET}", flush=True)
    print(f"{BOLD}  Invis Raspberry Pi Firmware & Communication Test Suite (macOS)  {RESET}", flush=True)
    print(f"{BOLD}{GREEN}=================================================================={RESET}", flush=True)

    print(f"\n{BOLD}{CYAN}=== 1. Testing MicroPython Firmware (pico-firmware/micropython/main.py) ==={RESET}", flush=True)
    run_micropython_tests()

    print(f"\n{BOLD}{CYAN}=== 2. Testing C / TinyUSB Firmware (pico-firmware/main.c) ==={RESET}", flush=True)
    run_c_firmware_tests()

    print(f"\n{BOLD}{CYAN}=== 3. Testing Dongle Emulator & Protocol Integration ==={RESET}\n", flush=True)
    run_integration_tests()

    print(f"\n{BOLD}{GREEN}✔ ALL RASPBERRY PI FIRMWARE & LOGIC TESTS COMPLETED SUCCESSFULLY!{RESET}\n", flush=True)

if __name__ == "__main__":
    main()
