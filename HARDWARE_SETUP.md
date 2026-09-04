# Physical Wired USB Hardware & Cable Connection Guide

This document specifies the exact physical wiring, cable configurations, and hardware pinouts required to connect the **Raspberry Pi Pico (RP2040)** dongle to Apple devices (**iPhone** or **Mac**) strictly over a wired USB connection with zero wireless/radio reliance.

---

## 1. Setup A: iPhone Direct Connection (iOS)

Because iOS restricts raw USB-serial (CDC-ACM) without an Apple MFi authentication chip, the Pico operates as a standard **USB Network Gadget (CDC-NCM Ethernet-over-USB)**. When plugged in, iOS recognizes the Pico as a physical wired Ethernet adapter and automatically assigns a link-local subnet (`192.168.7.x`).

```
┌─────────────────────────┐
│     iPhone (iOS App)    │
│  MapKit + Network.fw    │
└────────────┬────────────┘
             │
      [Physical Cable]
             │
             ▼
┌─────────────────────────┐
│   Raspberry Pi Pico     │
│ TinyUSB CDC-NCM / RNDIS │
│   TCP Server :9000      │
└─────────────────────────┘
```

### Cable & Adapter Requirements:

#### Option 1: iPhone 15, 16, & iPad (USB-C Port)
1. **Direct USB-C Host Cable**:
   - Cable: **USB-C to Micro-USB OTG Cable** (e.g., CableCreation / UGREEN USB-C to Micro-USB 480Mbps Data Cable).
   - Alternatively: If using a board with native USB-C (e.g. Raspberry Pi Pico 2, Waveshare RP2040-Plus, or Adafruit KB2040), a standard **USB-C to USB-C data cable** can be used.
2. **Behavior**: The iPhone provides 5V VBUS power to the Pico and automatically mounts the link-local Ethernet interface.

#### Option 2: iPhone 14 & Earlier (Lightning Port)
1. **Apple Lightning to USB 3 Camera Adapter** (Model `MK0W2AM/A`):
   - Lightning connector plugs into the iPhone.
   - Standard USB-A port accepts standard USB-A to Micro-USB cable to the Pico.
   - Lightning power input port receives power from a charger or power bank to supply steady 5V 500mA VBUS to the Pico.
2. **Behavior**: Provides full data transfer and prevents iPhone battery drain or "Accessory consumes too much power" warnings.

---

## 2. Setup B: iPhone Connected to MacBook via USB-C Cable (Host Emulation Mode)

When the physical iPhone running the Invis iOS app is connected to a MacBook via standard USB-C cable, it functions identically to being connected to a physical Pico dongle:

```
┌─────────────────────────┐
│     iPhone (iOS App)    │
│   NWListener Port 9000  │
└────────────┬────────────┘
             │
      [USB-C Cable]
             │
             ▼
┌─────────────────────────┐
│       MacBook Host      │
│  mac_bridge.py (usbmux) │
│ Apple DVT LocationSim   │
└─────────────────────────┘
```

### Connection Characteristics:
- Standard **USB-C to USB-C data cable** (or Lightning to USB-C cable).
- Plugs into any MacBook Thunderbolt / USB-C port.
- No Wi-Fi or personal hotspot required: Apple's native `usbmuxd` tunnels communication through the physical USB cable directly into the iOS app's port 9000.
- `scripts/mac_bridge.py` receives the exact same JSON commands as the Pico (`teleport`, `route`, `jitter`, `reset`) and applies them to the iPhone via Apple DVT `LocationSimulation`.

---

## 3. Raspberry Pi Pico Hardware Pinout & Wiring Diagram

```
                             Raspberry Pi Pico (RP2040)
                                    ┌─────────┐
             [UART0 TX / NMEA] GP0  │ 1    40 │  VBUS (5V In from USB Cable)
             [UART0 RX]        GP1  │ 2    39 │  VSYS
                               GND  │ 3    38 │  GND (System Ground)
                               GP2  │ 4    37 │  3V3_EN
                               GP3  │ 5    36 │  3V3 (Out)
                               GP4  │ 6    35 │  ADC_VREF
                               GP5  │ 7    34 │  GP28
                               GND  │ 8    33 │  GND
                               GP6  │ 9    32 │  GP27
                               GP7  │ 10   31 │  GP26
                               GP8  │ 11   30 │  RUN
                               GP9  │ 12   29 │  GP22
                               GND  │ 13   28 │  GND
                              GP10  │ 14   27 │  GP21
                              GP11  │ 15   26 │  GP20
                              GP12  │ 16   25 │  GP25 (On-board Activity LED)
                              GP13  │ 17   24 │  GP19
                               GND  │ 18   23 │  GND
                              GP14  │ 19   22 │  GP18
                              GP15  │ 20   21 │  GP17
                                    └────┬────┘
                                         │
                                   [Micro-USB]
                                   D+ / D- / 5V / GND
```

### Pin Assignment Table:

| Pin Name | Physical Pin | Direction | Description |
|---|---|---|---|
| **Micro-USB** | Port | Bi-dir | USB Full Speed (12 Mbps) data link to iPhone/Mac |
| **VBUS** | Pin 40 | Power In | 5.0V power directly from host USB cable |
| **GND** | Pin 38 | Power | Ground return |
| **GP0 (TX0)** | Pin 1 | Output | Emits standard NMEA 0183 ($GPGGA, $GPRMC) at 9600 baud |
| **GP1 (RX0)** | Pin 2 | Input | Optional serial input for external GNSS diagnostics |
| **GP25 (LED)**| Internal | Output | Status LED: Blinks on command RX/TX; solid on Safe-Hold |

---

## 4. Anti-Rubberbanding & Failsafe Architecture

```
[Host App Streaming Coordinates]
               │
               ▼
   ┌───────────────────────┐
   │    Heartbeat Ping     │  Every 1.0s
   │      (RTT < 3ms)      │
   └───────────┬───────────┘
               │
               ├───────────────────┬───────────────────┐
               │ Cable Connected   │ Cable Severed     │
               ▼                   ▼                   ▼
     [Normal Simulation]   [Timeout > 3.5s]    [User Reconnects]
     - Coordinates update  - Anti-Rubberband   - Handshake resumes
     - Micro-jitter active - FREEZES POSITION  - No coordinate jumps
     - LED pulses          - Solid Warning LED
```

1. **Host Heartbeat**: App issues `ping` every 1,000ms.
2. **Watchdog Timeout**: If no packet arrives for > 3,500ms (accidental cable unplug), the firmware immediately transitions to `STATE_SAFE_HOLD`.
3. **Anti-Rubberbanding Protection**: The Pico holds the last injected coordinate and does not jump back to 0.0 or allow the target device to snap abruptly back to physical location.
4. **Resumption**: As soon as the cable is re-plugged, the firmware recognizes the handshake and resumes seamless simulation.
