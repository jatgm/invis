# invis

<div align="center">

**Native Wired Location Simulation Interface for iOS**  
*Physical wired connection, zero wireless reliance, native Apple Maps integration, Turn-by-Turn road routing, Gaussian multi-path drift, and hardware failsafes.*

[![iOS 17.0+](https://img.shields.io/badge/iOS-17.0%2B-black?logo=ios)](https://www.apple.com/ios/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![Raspberry Pi Pico](https://img.shields.io/badge/RP2040-Pico%20%2F%20Pico%20W-crimson?logo=raspberrypi)](https://www.raspberrypi.com/products/raspberry-pi-pico/)
[![Mac Bridge](https://img.shields.io/badge/Mac%20Bridge-usbmuxd-blue?logo=apple)](scripts/mac_bridge.py)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## GitHub Repository Description

> **Suggested GitHub About Description**:  
> *Native iOS wired location simulation interface with Apple Maps integration, turn-by-turn road routing, Gaussian drift, and dual hardware bridge support (MacBook usbmuxd & Raspberry Pi Pico RP2040).*

**Suggested Topics / Tags**:  
`ios`, `swift`, `swiftui`, `mapkit`, `corelocation`, `location-simulation`, `gps-spoofing`, `raspberry-pi-pico`, `rp2040`, `usbmuxd`, `dvt`, `hardware-bridge`

---

## Overview

**Invis** is a native iOS location simulation interface engineered for physical iPhones and iPads. The iOS app operates strictly as an interactive control surface for location firmware—providing sub-millisecond coordinate streaming, road-geometry route playback, and Gaussian position drift over a **physical wired connection** with zero wireless or radio reliance.

The system supports two complementary operating topologies:
1. **MacBook USB-C Mode (Physical iPhone + Mac)**: Connect your iPhone to a MacBook via standard USB-C cable and launch `./run_bridge.sh`. The Mac daemon connects over Apple's native `usbmuxd` USB tunnel, relaying commands to Apple's DVT `LocationSimulation` protocol. The iPhone app runs seamlessly as if connected to dedicated hardware!
2. **Standalone Hardware Dongle Mode (Raspberry Pi Pico)**: Plug your iPhone directly into a Raspberry Pi Pico (RP2040) dongle via USB-C OTG. The Pico operates as a USB CDC-NCM Ethernet gadget (`192.168.7.1:9000`) with an onboard hardware UART NMEA 0183 bridge.

---

## Architecture

```mermaid
graph TD
    subgraph "Mode 1: iPhone Connected to MacBook via USB-C"
        iPhoneApp1[Invis iOS App on iPhone] <-->|Physical USB-C / usbmuxd :9000| MacBridge[Mac USB Bridge Daemon mac_bridge.py]
        MacBridge -->|Apple DVT LocationSimulation| DVT[CoreDevice RSD Tunnel]
        DVT -->|System Location Injection| iPhoneGPS1[iPhone CoreLocation System]
    end

    subgraph "Mode 2: Standalone Pico Hardware Dongle"
        iPhoneApp2[Invis iOS App on iPhone] <-->|Physical USB-C OTG / CDC-NCM :9000| Pico[Raspberry Pi Pico RP2040]
        Pico -->|UART0 GP0 TX 9600 Baud| NMEA[External GNSS / NMEA 0183 Receiver]
    end
```

---

## Key Features

- **Native MapKit & Liquid Glass Interface**:
  - Interactive Apple Maps canvas with Apple's real native controls (`MapUserLocationButton`, `MapCompass`, `MapPitchToggle`).
  - Automatic physical location acquisition via CoreLocation: the app starts centered on the user's authentic device coordinates.
  - Native sheet presentation with background interaction (`presentationBackgroundInteraction(.enabled)`), allowing simultaneous panning, pinching, and sheet navigation.
  - Curated landmark presets (Apple Park, Times Square, Eiffel Tower, Shibuya Crossing, and more) with semantic SF Symbols and zero emojis.

- **Sub-Millisecond Heartbeat & Link Diagnostics**:
  - Continuous ping/pong latency telemetry (typically <1.5 ms over physical USB).
  - Status header displaying live link health, firmware version, and connected device metadata.

- **Failsafe Anti-Rubberbanding**:
  - If the physical USB link is severed mid-simulation, the firmware automatically holds coordinates within 3.5 seconds.
  - Freezes the last active coordinates to prevent the device from abruptly snapping back to real GPS.
  - Automatically resumes normal simulation once the link is re-established.

- **Natural Position Drift (Gaussian Variance)**:
  - Emulates authentic atmospheric GNSS multi-path drift using a Box-Muller $\mathcal{N}(0, \sigma^2)$ random walk algorithm.
  - Configurable drift radius (0.5m – 5.0m) to reflect realistic device variance.
  - Automatically pauses drift when vehicle velocity exceeds 1.0 km/h.

- **Turn-by-Turn Road Route Simulation**:
  - Fetches real road polylines from Apple Maps (`MKDirections`) between any origin and destination.
  - Travel profiles: **Walk** (5 km/h), **Cycle** (20 km/h), **Drive** (50 km/h), and **Express** (85 km/h).
  - Variable speed multiplier slider (0.5× to 4.0×) with corner easing and traffic fluctuation simulation.
  - Transport controls: Start, Pause, Resume, Stop, and Continuous Loop playback.

- **Dual Hardware Dongle Firmware (RP2040)**:
  - **C / TinyUSB**: Native UF2 binary built with the Raspberry Pi Pico SDK.
  - **MicroPython**: Drop-in Python script for fast, toolchain-free deployment.
  - Real-time hardware UART NMEA emission (`$GPGGA`, `$GPRMC`) with CRC verification.

- **Hardware Safety Reset**:
  - One-tap **"Restore Hardware GPS"** action instantly clears all simulation overrides and restores authentic satellite GPS reception.

---

## Repository Structure

```
invis/
├── invis/                       # Native iOS Application (SwiftUI + MapKit)
│   ├── ContentView.swift        # Main container with native sheet & background interaction
│   ├── MapView.swift            # Native MapKit with UserAnnotation & MapControls
│   ├── ControlsView.swift       # Coordinate inputs, presets, position drift, telemetry
│   ├── RoutePlannerView.swift   # Turn-by-turn road routing & playback engine
│   ├── UserLocationManager.swift# CoreLocation manager for physical GPS initialization
│   ├── LiquidGlass.swift        # Apple Liquid Glass design modifiers & haptics
│   ├── LocationEngine.swift     # Geodesic math, timelines, Gaussian drift
│   ├── WiredConnectionManager.swift # Dual-mode USB connection manager (usbmux & NCM)
│   └── WiredStatusView.swift    # Status indicator & latency diagnostics
├── pico-firmware/               # Raspberry Pi Pico (RP2040) Hardware Firmware
│   ├── main.c                   # Native C / TinyUSB firmware with failsafe watchdog
│   ├── CMakeLists.txt           # Pico SDK build configuration
│   ├── tusb_config.h            # TinyUSB CDC configuration
│   ├── usb_descriptors.c        # USB descriptor tables
│   └── micropython/
│       └── main.py              # Pure MicroPython firmware implementation
├── scripts/
│   ├── mac_bridge.py            # Universal Mac USB bridge for physical iPhone (usbmuxd)
│   ├── device_bridge.py         # Backward-compatibility alias for mac_bridge.py
│   ├── mock_pico_dongle.py      # Hardware emulator for local testing
│   └── test_cli.py              # Master test runner
├── tests/                       # Automated Firmware & Logic Test Suites
│   ├── test_pico_micropython.py # MicroPython unit tests with mocked hardware
│   ├── test_pico_c.c            # Native C unit tests compiled via clang
│   └── mock_pico/               # Lightweight mock headers for Pico SDK & TinyUSB
├── run_bridge.sh                # Automated launcher with .venv setup
├── requirements.txt             # Python bridge dependencies
├── BUILD_GUIDE.md               # Detailed compilation & Xcode setup guide
└── HARDWARE_SETUP.md            # Physical pinouts, wiring diagrams & OTG cables
```

---

## Quick Start
 
### 1. Build & Run the Invis iOS App

#### Prerequisites
- macOS 14.0+ with Xcode 15+ / 16+
- Physical iPhone (iOS 17.0+) or iOS Simulator

#### Clone & Open
```bash
git clone https://github.com/jatgm/invis.git
cd invis
open invis.xcodeproj
```

#### Build from Terminal
```bash
# Build for iOS Simulator
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcodebuild \
  -scheme invis -destination 'generic/platform=iOS Simulator' build

# Build for Physical iPhone
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcodebuild \
  -scheme invis -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

---

### 2. MacBook USB-C Cable Mode (iPhone Connected to Mac)

When your iPhone is plugged into your MacBook via USB-C cable:

1. Connect your iPhone to your Mac with a standard USB-C cable.
2. Start the Mac USB bridge (automatically creates `.venv` and installs dependencies):
   ```bash
   ./run_bridge.sh
   ```
3. Launch **Invis** on your iPhone. The top status banner will show **MacBook USB Bridge** with sub-2ms ping latency.
4. The map will prompt for location access and center on your actual physical location.
5. Select any target or route on your phone, tap **Simulate Location**, and observe your phone's real system location update live across all apps.
6. Tap **Restore Hardware GPS** to restore physical authentic hardware GPS at any time.

---

### 3. Raspberry Pi Pico Hardware Dongle

#### Option A: MicroPython Deployment (Fastest)
1. Download standard MicroPython `.uf2` for Pico from [raspberrypi.com](https://www.raspberrypi.com/documentation/microcontrollers/micropython.html).
2. Hold **BOOTSEL** while plugging the Pico into your Mac, then copy the `.uf2` file to the `RPI-RP2` volume.
3. Install `mpremote` and copy the firmware:
   ```bash
   pip install mpremote
   mpremote cp pico-firmware/micropython/main.py :main.py
   mpremote reset
   ```

#### Option B: Compile Native C Firmware with Pico SDK
```bash
cd pico-firmware
mkdir -p build && cd build
cmake ..
make -j4
```
Hold **BOOTSEL**, plug in the Pico, and drag `pico_location_spoofer.uf2` onto the `RPI-RP2` drive.

#### Hardware Pinout Reference

```
                             Raspberry Pi Pico (RP2040)
                                    ┌─────────┐
              [UART0 TX / NMEA] GP0  │ 1    40 │  VBUS (5V In from USB Cable)
              [UART0 RX]        GP1  │ 2    39 │  VSYS
                                GND  │ 3    38 │  GND (System Ground)
                                     ...       ...
                              GP25  │ 16   25 │  GP25 (On-board Status LED)
                                     └────┬────┘
                                          │
                                    [Micro-USB]
                                  D+ / D- / 5V / GND
```

See [HARDWARE_SETUP.md](HARDWARE_SETUP.md) for cable specifications, Lightning camera adapters, and link-local Ethernet configuration.

---

## Testing & Verification

Run the master automated test runner to verify firmware logic, C state machines, and socket protocol integration:

```bash
python3 scripts/test_cli.py
```

This runs:
1. **MicroPython Unit Tests** (`tests/test_pico_micropython.py`): Validates RP2040 `machine.Pin`, `machine.UART`, ping/pong, teleport, NMEA checksums, drift, watchdog timeout, and safety killswitch.
2. **Native C Firmware Unit Tests** (`tests/test_pico_c.c`): Compiles `pico-firmware/main.c` natively with `clang` to validate JSON parsing, coordinate precision, NMEA 0183 output, and anti-rubberbanding failsafes.
3. **Protocol Integration Tests** (`scripts/mock_pico_dongle.py`): Validates TCP socket communication on port 9000.

---

## Safety & Legal Disclaimer

This software is intended strictly for development, debugging, and academic research purposes (such as testing location-aware applications, geofences, and navigation software in lab environments). Users are responsible for complying with all applicable terms of service and local laws.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
