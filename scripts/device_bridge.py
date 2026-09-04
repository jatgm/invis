#!/usr/bin/env python3
"""
device_bridge.py - Alias for mac_bridge.py (Universal Mac USB Bridge for Invis iOS App).
"""

import sys
import os
import warnings

# Suppress macOS LibreSSL 2.8.3 warning emitted by urllib3 v2 on system Python
warnings.filterwarnings("ignore", message=".*LibreSSL.*")
warnings.filterwarnings("ignore", message=".*urllib3 v2 only supports OpenSSL.*")

# Delegate directly to mac_bridge.py
if __name__ == "__main__":
    from mac_bridge import main
    import asyncio
    asyncio.run(main())
