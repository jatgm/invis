# Invis Build & Setup Guide

This guide walks through configuring and running the **Invis** iOS app, connecting to firmware (Raspberry Pi Pico dongle or MacBook USB bridge), and testing the physical wired connection.

---

## 1. Prerequisites

- **Development Host:** macOS 14.0+ with Xcode 15+ / 16+.
- **Target Device:**
  - Physical iPhone or iPad running iOS 17.0+ (or iOS Simulator).
- **Hardware Connection Options:**
  - **Option A (MacBook USB Mode):** Standard USB-C data cable connecting iPhone to MacBook.
  - **Option B (Pico Dongle Mode):** Raspberry Pi Pico (RP2040) dongle + USB-C OTG cable (or Lightning to USB 3 Camera Adapter).

---

## 2. Xcode Project Setup

The project targets iOS devices (`iphoneos`, `iphonesimulator`).

### A. Open in Xcode
```bash
git clone https://github.com/jatgm/invis.git
cd invis
open invis.xcodeproj
```

### B. Capabilities & Network Access
The project includes `invis/invis.entitlements` and standard iOS capabilities:
- Local Network access: Allows TCP communication with the USB-C link-local listener (port 9000) and Pico Ethernet gadget (`192.168.7.1:9000`).
- CoreLocation support: MapKit interactive location display.

---

## 3. Building & Running from the Command Line

### Build for iOS Simulator:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcodebuild \
  -scheme invis \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Build for Physical iPhone:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcodebuild \
  -scheme invis \
  -destination 'generic/platform=iOS' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

---

## 4. Running the System

### Mode 1: iPhone Connected to MacBook via USB-C Cable
1. Connect your iPhone to your MacBook with a standard USB-C cable.
2. In Terminal on the Mac, start the Mac USB bridge daemon:
   ```bash
   python3 -m venv .venv
   .venv/bin/pip install pymobiledevice3
   .venv/bin/python3 scripts/mac_bridge.py
   ```
3. Open **Invis** on your iPhone.
4. The top status bar will immediately transition to **MacBook USB Bridge** with sub-2ms ping latency.
5. Tap anywhere on the map to set a location, or plan a route, and tap **Spoof Location**. The location updates natively on the phone.
6. Tap **Reset GPS** to restore physical GPS.

### Mode 2: Standalone Raspberry Pi Pico Dongle Mode
1. Flash MicroPython or C firmware onto the Pico (see `pico-firmware/` directory).
2. Connect the Pico to the iPhone using a USB-C to Micro-USB OTG cable (or Lightning camera adapter).
3. Open **Invis** on your iPhone.
4. The app detects the Pico CDC-NCM Ethernet gadget on `192.168.7.1:9000` and displays **Pico Hardware Dongle**.

---

## 5. Troubleshooting

| Issue | Root Cause | Solution |
|---|---|---|
| **Status remains "Hardware Disconnected"** | Cable is charge-only or Mac bridge is not running | Ensure `scripts/mac_bridge.py` is running on the Mac and the USB-C cable supports data. |
| **Pico dongle not recognized** | Missing OTG pinout or insufficient power | Use an Apple-certified Camera Adapter or host-mode OTG cable with VBUS power. |
| **MKDirections route fails** | Coordinates too close or across oceans | Ensure Start and Destination are connected by road, or rely on the automatic Haversine geodesic fallback. |
