#!/bin/bash
#
# Thermal Management System - Complete Uninstaller
# Removes both old (pre-update) and new installations
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="thermal-manager"

echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   Thermal Management System - Uninstaller             ║${NC}"
echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

echo -e "${YELLOW}⚠ WARNING: This will completely remove the thermal management system${NC}"
echo ""
echo "This uninstaller will:"
echo "  - Stop and disable the systemd service"
echo "  - Remove service files"
echo "  - Clean up old installations (pre-update versions)"
echo "  - Optionally remove log files"
echo "  - Optionally remove the installation directory"
echo ""

read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Uninstall cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${GREEN}[1/6]${NC} Stopping service..."

# Check if service exists and stop it
if sudo systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    if sudo systemctl is-active --quiet ${SERVICE_NAME}.service 2>/dev/null; then
        sudo systemctl stop ${SERVICE_NAME}.service
        echo -e "${GREEN}✓ Service stopped${NC}"
    else
        echo -e "${BLUE}ℹ Service was not running${NC}"
    fi
else
    echo -e "${BLUE}ℹ Service not found${NC}"
fi

echo ""
echo -e "${GREEN}[2/6]${NC} Disabling and removing service..."

# Disable and remove service
if sudo systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    sudo systemctl disable ${SERVICE_NAME}.service 2>/dev/null || true
    echo -e "${GREEN}✓ Service disabled${NC}"
fi

# Remove service file from systemd directory
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    sudo rm -f /etc/systemd/system/${SERVICE_NAME}.service
    echo -e "${GREEN}✓ Service file removed from /etc/systemd/system/${NC}"
fi

# Reload systemd daemon
sudo systemctl daemon-reload
sudo systemctl reset-failed 2>/dev/null || true
echo -e "${GREEN}✓ Systemd reloaded${NC}"

echo ""
echo -e "${GREEN}[3/6]${NC} Cleaning up old installation artifacts..."

# Remove old log file locations (pre-update versions)
OLD_LOG_LOCATIONS=(
    "/home/mesh/thermal_manager.log"
    "/home/pi/thermal_manager.log"
    "/root/thermal_manager.log"
    "/tmp/thermal_manager.log"
)

REMOVED_OLD_LOGS=0
for log_file in "${OLD_LOG_LOCATIONS[@]}"; do
    if [ -f "$log_file" ]; then
        sudo rm -f "$log_file"
        echo -e "${GREEN}  ✓ Removed old log: ${log_file}${NC}"
        REMOVED_OLD_LOGS=$((REMOVED_OLD_LOGS + 1))
    fi
done

if [ $REMOVED_OLD_LOGS -eq 0 ]; then
    echo -e "${BLUE}  ℹ No old log files found${NC}"
fi

# Check for old service files with hardcoded paths
OLD_SERVICE_LOCATIONS=(
    "/home/mesh/thermal-manager.service"
    "/home/pi/thermal-manager.service"
)

REMOVED_OLD_SERVICE=0
for service_file in "${OLD_SERVICE_LOCATIONS[@]}"; do
    if [ -f "$service_file" ]; then
        sudo rm -f "$service_file"
        echo -e "${GREEN}  ✓ Removed old service file: ${service_file}${NC}"
        REMOVED_OLD_SERVICE=$((REMOVED_OLD_SERVICE + 1))
    fi
done

if [ $REMOVED_OLD_SERVICE -eq 0 ]; then
    echo -e "${BLUE}  ℹ No old service files found${NC}"
fi

echo ""
echo -e "${GREEN}[4/6]${NC} Handling log directory..."

# Check new log directory
if [ -d "/var/log/thermal-manager" ]; then
    echo -e "${YELLOW}  Log directory found: /var/log/thermal-manager${NC}"

    # Show log size
    LOG_SIZE=$(du -sh /var/log/thermal-manager 2>/dev/null | cut -f1)
    echo -e "${BLUE}  Size: ${LOG_SIZE}${NC}"

    read -p "  Remove log files? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo rm -rf /var/log/thermal-manager
        echo -e "${GREEN}  ✓ Log directory removed${NC}"
    else
        echo -e "${BLUE}  ℹ Log directory preserved${NC}"
    fi
else
    echo -e "${BLUE}ℹ No log directory found${NC}"
fi

echo ""
echo -e "${GREEN}[5/6]${NC} Checking for running processes..."

# Kill any remaining thermal heater processes
HEATER_PIDS=$(ps aux | grep -E "thermal_heater|thermal_manager" | grep -v grep | awk '{print $2}')
if [ -n "$HEATER_PIDS" ]; then
    echo -e "${YELLOW}  Found running thermal processes${NC}"
    echo "$HEATER_PIDS" | while read pid; do
        sudo kill -9 $pid 2>/dev/null || true
        echo -e "${GREEN}  ✓ Terminated process: ${pid}${NC}"
    done
else
    echo -e "${BLUE}ℹ No running thermal processes found${NC}"
fi

echo ""
echo -e "${GREEN}[6/6]${NC} Installation directory..."

echo -e "${YELLOW}  Current directory: ${SCRIPT_DIR}${NC}"
echo ""
read -p "  Remove installation directory? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Move out of the directory before removing it
    cd /tmp

    echo -e "${YELLOW}  ⚠ Removing ${SCRIPT_DIR}...${NC}"
    sudo rm -rf "$SCRIPT_DIR"
    echo -e "${GREEN}  ✓ Installation directory removed${NC}"
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Uninstall Complete! ✓                         ║${NC}"
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo ""
    echo -e "${BLUE}The thermal management system has been completely removed.${NC}"
    echo -e "${BLUE}You are now in /tmp directory.${NC}"
else
    echo -e "${BLUE}  ℹ Installation directory preserved${NC}"
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Uninstall Complete! ✓                         ║${NC}"
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo ""
    echo -e "${BLUE}Service and systemd files removed.${NC}"
    echo -e "${BLUE}Installation directory preserved at: ${SCRIPT_DIR}${NC}"
    echo ""
    echo -e "${YELLOW}To reinstall, run: ./install.sh${NC}"
fi

echo ""
echo -e "${GREEN}Summary of what was removed:${NC}"
echo "  ✓ Systemd service (${SERVICE_NAME}.service)"
echo "  ✓ Service configuration files"
echo "  ✓ Old installation artifacts"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  ✓ Installation directory"
fi
echo ""

# Final verification
if ! sudo systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    echo -e "${GREEN}✓ Verified: No thermal-manager service remains${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Service file may still exist, manual cleanup may be needed${NC}"
fi

echo ""
echo -e "${BLUE}Thank you for using the Thermal Management System!${NC}"
echo ""
