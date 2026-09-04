#!/usr/bin/env python3
"""
device_bridge.py - Alias for mac_bridge.py (Universal Mac USB Bridge for Invis iOS App).
"""

import sys
import os

# Delegate directly to mac_bridge.py
if __name__ == "__main__":
    from mac_bridge import main
    import asyncio
    asyncio.run(main())
