# Invis Build & Setup Guide

This guide walks through configuring and running the **Invis** location simulation suite on macOS and iOS, compiling the Raspberry Pi Pico firmware, and testing the physical wired USB connection.

---

## 1. Prerequisites

- **Host Machine:** macOS 14.0+ with Xcode 15+ / 16+ (tested on Xcode 26.6 with Swift 6.3).
- **Hardware:**
  - Raspberry Pi Pico (RP2040) or Pico W.
  - USB data cable (USB-C or Lightning OTG adapter).
- **Target OS:**
  - macOS 14.0+ (native desktop app).
  - iOS 17.0+ (physical iPhone or iOS Simulator).

---

## 2. Xcode Project Setup

The project is pre-configured with multiplatform support (`macosx`, `iphoneos`, `iphonesimulator`).

### A. Open in Xcode
```bash
cd /Users/jasonzhou/Developer/invis
open invis.xcodeproj
```

### B. App Sandbox & Entitlements
The project includes `invis/invis.entitlements` with the required capabilities:
- `com.apple.security.app-sandbox`: Enabled.
- `com.apple.security.network.client`: Allows TCP/HTTP communication over the link-local wired USB network (`192.168.7.1`).
- `com.apple.security.device.serial`: Allows opening USB CDC-ACM virtual serial devices (`/dev/cu.usbmodem*`).
- `com.apple.security.device.usb`: Direct USB device access.
- `com.apple.security.personal-information.location`: CoreLocation user location support.

To verify in Xcode:
1. Select the **invis** project in the Project Navigator.
2. Select the **invis** target under Targets.
3. Click the **Signing & Capabilities** tab.
4. Verify that **App Sandbox** includes:
   - **Outgoing Connections (Client)**: Checked
   - **Hardware > Serial Port**: Checked
   - **Hardware > USB**: Checked

---

## 3. Building & Running from the Command Line

You can build either platform directly from Terminal:

### macOS Build:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcodebuild \
  -scheme invis \
  -destination 'generic/platform=macOS' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### iOS Simulator Build:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcodebuild \
  -scheme invis \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

---

## 4. Raspberry Pi Pico Dongle Preparation

### Option A: Flash Pre-compiled MicroPython (Fastest)
1. Download standard MicroPython `.uf2` for Pico from [raspberrypi.com/documentation/microcontrollers/micropython.html](https://www.raspberrypi.com/documentation/microcontrollers/micropython.html).
2. Hold **BOOTSEL** while plugging the Pico into your Mac, then copy the MicroPython `.uf2` to the `RPI-RP2` drive.
3. Copy `pico-firmware/micropython/main.py` onto the device:
   ```bash
   pip install mpremote
   mpremote cp pico-firmware/micropython/main.py :main.py
   mpremote reset
   ```

### Option B: Build C/C++ UF2 Binary with Pico SDK
```bash
cd pico-firmware
mkdir -p build && cd build
cmake ..
make -j4
```
Hold **BOOTSEL**, connect Pico, and drop `pico_location_spoofer.uf2` into `RPI-RP2`.

---

## 5. Connecting the Hardware & Running the Simulation

1. **Plug in the Pico Dongle**:
   - On **Mac**: Connect via standard USB cable.
   - On **iPhone**: Connect via USB-C to Micro-USB OTG cable (or Lightning to USB 3 Camera Adapter).
2. **Launch the Invis App**:
   - The status bar at the top will change from gray (`Hardware Disconnected`) to animated green (`Pico Dongle Connected`).
   - The latency readout (e.g. `⚡ 1.8 ms`) confirms physical USB communication.
3. **Instant Location Spoofing**:
   - Tap anywhere on the Apple Maps view to drop the Target Pin.
   - Or select a preset (e.g., *Apple Park*, *Times Square*, *Eiffel Tower*).
   - Click **Spoof Location**. The blue pulsing beacon on the map represents the active spoofed coordinate.
4. **Natural GPS Micro-Jitter**:
   - Toggle **Realistic Micro-Jitter** on.
   - Adjust the radius slider (0.5m – 5.0m) to evade static location detection.
5. **Route Planning & Simulation**:
   - Switch to the **Route Planner** tab.
   - Choose travel profile: **Walk (5 km/h)**, **Cycle (20 km/h)**, **Drive (50 km/h)**, or **Express (85 km/h)**.
   - Click **Calculate Turn-by-Turn Route** to fetch actual road polylines from Apple Maps (`MKDirections`).
   - Click **Start Route** to begin real-time route simulation.
6. **Safety Killswitch**:
   - Click **Reset to Physical GPS (Killswitch)** at any time to instantly cancel spoofing and restore the device's authentic hardware GPS.

---

## 6. Troubleshooting

| Issue | Root Cause | Solution |
|---|---|---|
| **Status remains "Hardware Disconnected"** | Cable is charge-only or USB port not detected | Use a 4-wire USB data cable; click "Detect" in the status bar. |
| **macOS Permission Denied opening /dev/cu.usbmodem** | App Sandbox missing serial entitlement | Ensure `invis.entitlements` contains `com.apple.security.device.serial`. |
| **iPhone does not mount link-local network** | Missing OTG pinout or insufficient power | Use an Apple-certified Camera Adapter or host-mode OTG cable with VBUS power. |
| **MKDirections route fails** | Coordinates too close or across oceans | Ensure Start and Destination are connected by road, or rely on the automatic Haversine geodesic fallback. |
