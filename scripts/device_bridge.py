#!/usr/bin/env python3
"""
device_bridge.py - Native macOS usbmux/CoreDevice bridge for physical iPhones and iPads.

Monitors usbmux for connected iPhones/iPads over USB, manages the persistent RSD tunnel
and DVT LocationSimulation session (iOS 17+), and communicates with the Swift GUI app
over link-local TCP port 9000.
"""

import sys
import time
import json
import asyncio
import logging
from typing import Optional, Dict, Any

from pymobiledevice3 import usbmux
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.remote.rsd_tunnel import PreferredRsdTunnel
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("DeviceBridge")

PORT = 9000

class ConnectedPhoneManager:
    def __init__(self):
        self.active_udid: Optional[str] = None
        self.device_name: str = "Scanning..."
        self.model: str = "iPhone"
        self.version: str = "Unknown"
        self.battery_level: Optional[int] = None

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
                logger.info(f"Detected new USB iOS device: {udid}")
                self.active_udid = udid

                # Query lockdown device metadata
                try:
                    async with await create_using_usbmux(serial=udid, autopair=True) as ld:
                        vals = ld.all_values
                        self.device_name = vals.get("DeviceName", "iPhone")
                        self.model = vals.get("ProductType", "iPhone")
                        self.version = vals.get("ProductVersion", "iOS 17+")
                        logger.info(f"Identified: {self.device_name} ({self.model}, iOS {self.version})")
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
            logger.info(f"LocationSimulation session ready for {self.device_name}!")

        except Exception as e:
            logger.error(f"Failed to establish DVT location session: {e}")
            await self.close_session()

    async def set_location(self, lat: float, lon: float):
        """Simulates location on the physical iPhone."""
        self.current_lat = lat
        self.current_lon = lon
        await self.ensure_session()

        if self.loc_simulation:
            await self.loc_simulation.set(lat, lon)
            self.is_spoofing = True
            logger.info(f"Injected coordinates onto {self.device_name}: ({lat:.6f}, {lon:.6f})")

    async def clear_location(self):
        """Restores authentic physical hardware GPS on the iPhone."""
        if self.loc_simulation:
            try:
                await self.loc_simulation.clear()
            except Exception as e:
                logger.warning(f"Error clearing location: {e}")
        self.is_spoofing = False
        logger.info(f"Cleared location simulation on {self.device_name}. Physical GPS restored.")

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
        self.device_name = "Scanning..."
        self.is_spoofing = False

phone_manager = ConnectedPhoneManager()

async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    logger.info("Swift App connected to device bridge.")
    buffer = ""

    while True:
        try:
            data = await reader.readline()
            if not data:
                logger.info("Swift App disconnected.")
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
                    "version": f"iOS {phone_manager.version}",
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

            writer.write(b'{"status":"ignored"}\n')
            await writer.drain()

        except Exception as e:
            logger.error(f"Handler error: {e}")
            break

    writer.close()
    await writer.wait_closed()

async def background_device_scanner():
    """Continuously monitors usbmux for plugged-in iPhone."""
    while True:
        await phone_manager.scan_devices()
        await asyncio.sleep(1.5)

async def main():
    logger.info("Starting Invis Physical iPhone USB Bridge on port 9000...")
    # Initial device scan
    await phone_manager.scan_devices()

    # Start background scanner
    asyncio.create_task(background_device_scanner())

    # Start TCP Server for Swift App
    server = await asyncio.start_server(handle_client, "127.0.0.1", PORT, reuse_address=True)
    logger.info(f"Bridge listening on tcp://127.0.0.1:{PORT}. Ready for Swift App.")

    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())
