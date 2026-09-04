#!/usr/bin/env bash
#
# run_bridge.sh - Launch the Invis Mac USB Bridge Daemon
#
# Automatically creates the local Python virtual environment (.venv)
# and installs dependencies from requirements.txt if not already set up.
#

set -e

# Repository root directory
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$REPO_DIR/.venv"
REQ_FILE="$REPO_DIR/requirements.txt"

# ANSI Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}         Invis Mac USB Bridge Launcher                ${NC}"
echo -e "${CYAN}======================================================${NC}"

# Check for python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is not installed or not in PATH.${NC}"
    echo "Please install Python 3.9+ from python.org or via Homebrew (brew install python3)."
    exit 1
fi

# Check / create virtual environment
if [ ! -d "$VENV_DIR" ] || [ ! -f "$VENV_DIR/bin/python3" ]; then
    echo -e "${YELLOW}⚙ Creating Python virtual environment (.venv)...${NC}"
    python3 -m venv "$VENV_DIR"
    echo -e "${GREEN}✔ Virtual environment created.${NC}"

    echo -e "${YELLOW}⚙ Installing dependencies from requirements.txt...${NC}"
    "$VENV_DIR/bin/pip" install --quiet --upgrade pip
    "$VENV_DIR/bin/pip" install --quiet -r "$REQ_FILE"
    echo -e "${GREEN}✔ Dependencies installed successfully.${NC}"
else
    # Quick check if pymobiledevice3 is available in venv
    if ! "$VENV_DIR/bin/python3" -c "import pymobiledevice3" &> /dev/null; then
        echo -e "${YELLOW}⚙ Missing dependencies in .venv. Installing from requirements.txt...${NC}"
        "$VENV_DIR/bin/pip" install --quiet -r "$REQ_FILE"
        echo -e "${GREEN}✔ Dependencies installed.${NC}"
    fi
fi

echo -e "${GREEN}✔ Environment ready.${NC}"
echo -e "${CYAN}Starting Mac USB Bridge daemon...${NC}\n"

# Launch mac_bridge.py passing through any arguments
exec "$VENV_DIR/bin/python3" "$REPO_DIR/scripts/mac_bridge.py" "$@"
