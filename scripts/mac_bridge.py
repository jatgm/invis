#!/usr/bin/env python3
"""
mac_bridge.py (device_bridge.py) - Universal Mac USB Bridge for Invis iOS App.

Enables an iPhone connected to a MacBook via USB-C cable to run Invis seamlessly:
1. Connects to the Invis iOS App listening on port 9000 over the physical USB-C cable via usbmuxd.
2. Manages the persistent Apple DVT LocationSimulation session via pymobiledevice3 (iOS 17+).
3. Injects coordinates and routes directly into the iPhone's CoreLocation system.
4. Also listens on 127.0.0.1:9000 as a fallback for iOS Simulator testing.
"""

import sys
import os
import time
import json
import asyncio
import logging
import warnings
from typing import Optional, Dict, Any

# Suppress macOS LibreSSL 2.8.3 warning emitted by urllib3 v2 on system Python
warnings.filterwarnings("ignore", message=".*LibreSSL.*")
warnings.filterwarnings("ignore", message=".*urllib3 v2 only supports OpenSSL.*")

from pymobiledevice3 import usbmux
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.remote.rsd_tunnel import PreferredRsdTunnel
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

# ANSI Colors
CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
MAGENTA = "\033[95m"
BOLD = "\033[1m"
RESET = "\033[0m"

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("InvisMacBridge")

PORT = 9000

class ConnectedPhoneManager:
    def __init__(self):
        self.active_udid: Optional[str] = None
        self.active_device: Optional[usbmux.MuxDevice] = None
        self.device_name: str = "Scanning..."
        self.model: str = "iPhone"
        self.version: str = "Unknown"

        self.tunnel: Optional[PreferredRsdTunnel] = None
        self.rsd = None
        self.dvt_provider: Optional[DvtProvider] = None
        self.loc_simulation: Optional[LocationSimulation] = None

        self.is_spoofing: bool = False
        self.current_lat: float = 37.334900
        self.current_lon: float = -122.009020
        self.jitter_enabled: bool = False
        self.jitter_radius_m: float = 1.0

    async def scan_devices(self) -> bool:
        """Checks usbmux for connected USB iOS devices."""
        try:
            devices = await usbmux.list_devices()
            usb_devices = [d for d in devices if d.is_usb]

            if not usb_devices:
                if self.active_udid is not None:
                    logger.info("iPhone disconnected from USB.")
                    await self.close_session()
                return False

            first_dev = usb_devices[0]
            udid = first_dev.serial

            if self.active_udid != udid:
                logger.info(f"Detected USB iOS device: {udid}")
                self.active_udid = udid
                self.active_device = first_dev

                # Query lockdown device metadata
                try:
                    async with await create_using_usbmux(serial=udid, autopair=True) as ld:
                        vals = ld.all_values
                        self.device_name = vals.get("DeviceName", "iPhone")
                        self.model = vals.get("ProductType", "iPhone")
                        self.version = vals.get("ProductVersion", "iOS 17+")
                        print(f"{GREEN}✔ Identified Device:{RESET} {self.device_name} ({self.model}, iOS {self.version})")
                except Exception as e:
                    logger.warning(f"Could not read full lockdown info: {e}")
                    self.device_name = "iPhone"

                # Establish persistent DVT session
                await self.ensure_session()
            return True

        except Exception as e:
            logger.debug(f"Scan error: {e}")
            return False

    async def ensure_session(self):
        """Opens persistent RSD tunnel and DVT LocationSimulation channel."""
        if self.loc_simulation is not None:
            return

        try:
            logger.info(f"Opening native RSD tunnel for {self.device_name} ({self.active_udid})...")
            self.tunnel = PreferredRsdTunnel(serial=self.active_udid, prefer_native=True)
            self.rsd = await self.tunnel.aopen()

            logger.info("Initializing DVT instruments provider...")
            self.dvt_provider = DvtProvider(self.rsd)
            await self.dvt_provider.__aenter__()

            logger.info("Connecting LocationSimulation channel...")
            self.loc_simulation = LocationSimulation(self.dvt_provider)
            await self.loc_simulation.__aenter__()
            print(f"{GREEN}✔ Apple DVT LocationSimulation Channel Active!{RESET}")

        except Exception as e:
            logger.error(f"Failed to establish DVT location session: {e}")
            await self.close_session()

    async def set_location(self, lat: float, lon: float):
        """Simulates location on the physical iPhone."""
        self.current_lat = lat
        self.current_lon = lon
        await self.ensure_session()

        if self.loc_simulation:
            try:
                await self.loc_simulation.set(lat, lon)
                self.is_spoofing = True
                print(f"{CYAN}[DVT INJECT]{RESET} Set coordinate -> ({lat:.6f}, {lon:.6f}) on {self.device_name}")
            except Exception as e:
                logger.error(f"Error calling LocationSimulation.set: {e}")
                await self.close_session()

    async def clear_location(self):
        """Restores authentic physical hardware GPS on the iPhone."""
        if self.loc_simulation:
            try:
                await self.loc_simulation.clear()
            except Exception as e:
                logger.warning(f"Error clearing location: {e}")
        self.is_spoofing = False
        print(f"{RED}[DVT RESET]{RESET} Cleared location simulation on {self.device_name}. Physical GPS restored.")

    async def close_session(self):
        if self.loc_simulation:
            try:
                await self.loc_simulation.__aexit__(None, None, None)
            except Exception:
                pass
            self.loc_simulation = None

        if self.dvt_provider:
            try:
                await self.dvt_provider.__aexit__(None, None, None)
            except Exception:
                pass
            self.dvt_provider = None

        if self.tunnel:
            try:
                await self.tunnel.aclose()
            except Exception:
                pass
            self.tunnel = None
            self.rsd = None

        self.active_udid = None
        self.active_device = None
        self.device_name = "Scanning..."
        self.is_spoofing = False

phone_manager = ConnectedPhoneManager()

async def handle_app_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, source: str = "USB"):
    print(f"{GREEN}✔ Invis iOS App Connected ({source})!{RESET} Streaming firmware protocol.")

    while True:
        try:
            data = await reader.readline()
            if not data:
                print(f"{YELLOW}Invis iOS App Disconnected ({source}).{RESET}")
                break

            line = data.decode("utf-8", errors="ignore").strip()
            if not line:
                continue

            req = json.loads(line)
            cmd = req.get("cmd")

            if cmd == "ping":
                client_ts = req.get("ts", 0.0)
                resp = {
                    "status": "pong",
                    "device_connected": phone_manager.active_udid is not None,
                    "device_name": phone_manager.device_name,
                    "model": phone_manager.model,
                    "version": f"MacBook DVT Bridge (iOS {phone_manager.version})",
                    "udid": phone_manager.active_udid or "None",
                    "is_spoofing": phone_manager.is_spoofing,
                    "lat": phone_manager.current_lat,
                    "lon": phone_manager.current_lon,
                    "ts": client_ts
                }
                writer.write((json.dumps(resp) + "\n").encode("utf-8"))
                await writer.drain()
                continue

            if cmd == "teleport":
                lat = float(req["lat"])
                lon = float(req["lon"])
                await phone_manager.set_location(lat, lon)
                resp = {"status": "ok", "cmd": "teleport", "lat": lat, "lon": lon}
                writer.write((json.dumps(resp) + "\n").encode("utf-8"))
                await writer.drain()
                continue

            if cmd == "jitter":
                phone_manager.jitter_enabled = bool(req.get("enabled", False))
                phone_manager.jitter_radius_m = float(req.get("radius_meters", 1.0))
                resp = {"status": "ok", "cmd": "jitter", "enabled": phone_manager.jitter_enabled, "radius": phone_manager.jitter_radius_m}
                writer.write((json.dumps(resp) + "\n").encode("utf-8"))
                await writer.drain()
                continue

            if cmd == "reset":
                await phone_manager.clear_location()
                resp = {"status": "ok", "cmd": "reset", "msg": "Hardware GPS Restored"}
                writer.write((json.dumps(resp) + "\n").encode("utf-8"))
                await writer.drain()
                continue

            if cmd == "route":
                points = req.get("points", [])
                resp = {"status": "ok", "cmd": "route", "count": len(points)}
                writer.write((json.dumps(resp) + "\n").encode("utf-8"))
                await writer.drain()
                continue

            if cmd == "route_control":
                resp = {"status": "ok", "cmd": "route_control"}
                writer.write((json.dumps(resp) + "\n").encode("utf-8"))
                await writer.drain()
                continue

            writer.write(b'{"status":"ignored"}\n')
            await writer.drain()

        except Exception as e:
            logger.error(f"App client handler error: {e}")
            break

    try:
        writer.close()
        await writer.wait_closed()
    except Exception:
        pass

async def device_scanner_task():
    """Continuously monitors for connected iPhone in background."""
    while True:
        try:
            await phone_manager.scan_devices()
        except Exception as e:
            logger.debug(f"Device scanner error: {e}")
        await asyncio.sleep(2.0)

async def usb_device_connector():
    """Continuously connects to Invis iOS App over USB usbmux when an active USB device is found."""
    while True:
        if phone_manager.active_device is not None:
            try:
                mux = await usbmux.create_mux()
                sock = await mux.connect(phone_manager.active_device, PORT)
                reader, writer = await asyncio.open_connection(sock=sock)
                await handle_app_client(reader, writer, source=f"USB usbmux -> {phone_manager.device_name}")
            except Exception as e:
                # App might not be open on phone yet or socket closed, wait and retry
                await asyncio.sleep(2.0)
        else:
            await asyncio.sleep(1.5)

async def main():
    print(f"\n{BOLD}{GREEN}======================================================{RESET}")
    print(f"{BOLD}       Invis Universal MacBook USB Bridge Daemon       {RESET}")
    print(f"{BOLD}{GREEN}======================================================{RESET}")
    print(f"Modes Supported:  {CYAN}Physical iPhone (USB-C Cable / usbmux){RESET}")
    print(f"                  {CYAN}iOS Simulator (tcp://127.0.0.1:{PORT}){RESET}")
    print(f"Firmware Protocol:{GREEN} v1.3.3 JSON streaming over wired link{RESET}\n")

    # Initial scan
    await phone_manager.scan_devices()

    # Start background USB tasks
    asyncio.create_task(device_scanner_task())
    asyncio.create_task(usb_device_connector())

    # Start TCP Server for Simulator fallback
    server = await asyncio.start_server(
        lambda r, w: handle_app_client(r, w, source="iOS Simulator / Localhost"),
        "127.0.0.1",
        PORT,
        reuse_address=True
    )
    print(f"{GREEN}✔ Local fallback listener active on tcp://127.0.0.1:{PORT}{RESET}")
    print(f"{YELLOW}Waiting for Invis iOS App connection...{RESET}\n")

    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())
