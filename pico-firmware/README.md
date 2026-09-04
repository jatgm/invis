# Raspberry Pi Pico (RP2040) Location Simulation Dongle Firmware

This firmware turns a **Raspberry Pi Pico** or **Pico W** into a physical wired USB hardware dongle and location simulation runner for the **Invis** native Apple platform app.

---

## Features
- **Strict Physical Wired USB Connection**: Communicates over direct USB cable (CDC-ACM virtual serial or CDC-NCM Ethernet gadget).
- **Sub-Millisecond Ping / Heartbeat**: Real-time round-trip latency measurement and cable verification.
- **Payload Parser**: Handles newline-delimited JSON commands:
  - `{"cmd": "teleport", "lat": 37.774929, "lon": -122.419416, "alt": 15.0}`
  - `{"cmd": "jitter", "enabled": true, "radius_meters": 1.5}`
  - `{"cmd": "route", "points": [[...]], "speed": 50.0}`
  - `{"cmd": "reset"}`
  - `{"cmd": "ping", "ts": 1725400000.123}`
- **Failsafe Anti-Rubberbanding**:
  - If the USB cable is abruptly unplugged mid-simulation, the RP2040 state machine transitions to `STATE_SAFE_HOLD` within 3.5s and freezes injected coordinates to avoid abrupt location snaps.
- **Standalone Gaussian Micro-Jitter (Natural GPS Drift)**:
  - Generates realistic $\mathcal{N}(0, \sigma^2)$ micro-drift every 2.5 seconds when stationary.
- **Hardware NMEA Bridge (UART0 on GP0/GP1)**:
  - Simultaneously emits valid `$GPGGA` and `$GPRMC` NMEA 0183 sentences at 1 Hz (9600 baud).

---

## Method 1: Compile & Flash C/C++ Firmware (Recommended)

### Prerequisites
- Raspberry Pi Pico SDK (`PICO_SDK_PATH` set in environment)
- CMake 3.13+ and `arm-none-eabi-gcc`

### Build Steps
```bash
cd pico-firmware
mkdir build && cd build
cmake ..
make -j4
```
This generates `pico_location_spoofer.uf2`.

### Flashing via BOOTSEL
1. Press and hold the white **BOOTSEL** button on your Raspberry Pi Pico.
2. While holding the button, plug the Pico into your Mac's USB port.
3. Release the button. A mass storage device named `RPI-RP2` will mount in Finder.
4. Drag and drop `pico_location_spoofer.uf2` onto the `RPI-RP2` drive.
5. The Pico will reboot automatically and appear as a CDC-ACM device (`/dev/cu.usbmodem*`).

---

## Method 2: MicroPython Instant Deployment

If you do not have the C/C++ ARM toolchain installed:
1. Flash standard MicroPython firmware (`.uf2`) from [raspberrypi.com](https://www.raspberrypi.com/documentation/microcontrollers/micropython.html) onto your Pico.
2. Copy `pico-firmware/micropython/main.py` directly to the Pico flash root:
   ```bash
   pip install mpremote
   mpremote cp pico-firmware/micropython/main.py :main.py
   mpremote reset
   ```
3. The Pico will automatically execute `main.py` on boot whenever powered over USB.

---

## Pinout Reference

| Pin | Function | Description |
|---|---|---|
| **USB D+ / D-** | USB Data Bus | Direct physical link to iPhone or Mac |
| **VBUS (Pin 40)** | 5V Power In | Powered directly by host USB cable / OTG adapter |
| **GND (Pin 38)** | Ground | Ground reference |
| **GP0 (Pin 1)** | UART0 TX | Emits NMEA 0183 sentences ($GPGGA, $GPRMC) |
| **GP1 (Pin 2)** | UART0 RX | Optional NMEA serial input |
| **GP25 (LED)** | Status LED | Blinks on packet RX/TX; solid on safe hold |
