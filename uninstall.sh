#!/bin/bash
#
# Thermal Management System - Complete Uninstaller
# Removes both old (pre-update) and new installations
#
# Usage:
#   ./uninstall.sh        - Interactive uninstall with prompts
#   ./uninstall.sh --full - Complete removal without prompts (removes everything)
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

# Parse arguments
FULL_REMOVE=false
if [ "$1" = "--full" ] || [ "$1" = "-f" ]; then
    FULL_REMOVE=true
fi

echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   Thermal Management System - Uninstaller             ║${NC}"
echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

if [ "$FULL_REMOVE" = true ]; then
    echo -e "${YELLOW}⚠ FULL REMOVAL MODE - All files will be deleted without prompts${NC}"
    echo ""
    echo "This will remove:"
    echo "  - Systemd service"
    echo "  - Service files"
    echo "  - Log files"
    echo "  - Installation directory (including all git files)"
    echo "  - ANY other thermal-management installations found system-wide"
    echo ""
    read -p "Are you SURE you want to completely remove everything? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Uninstall cancelled${NC}"
        exit 0
    fi
else
    echo -e "${YELLOW}⚠ WARNING: This will remove the thermal management system${NC}"
    echo ""
    echo "This uninstaller will:"
    echo "  - Stop and disable the systemd service"
    echo "  - Remove service files"
    echo "  - Clean up old installations (pre-update versions)"
    echo "  - Search for and optionally remove installations in other locations"
    echo "  - Search for and optionally remove stray thermal manager files"
    echo "  - Optionally remove log files"
    echo "  - Optionally remove installation directory (all files including git)"
    echo ""
    echo -e "${BLUE}Tip: Use './uninstall.sh --full' for complete removal without prompts${NC}"
    echo ""

    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Uninstall cancelled${NC}"
        exit 0
    fi
fi

echo ""
echo -e "${GREEN}[1/10]${NC} Stopping service..."

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
echo -e "${GREEN}[2/10]${NC} Disabling and removing service..."

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
echo -e "${GREEN}[3/10]${NC} Removing command symlinks from PATH..."

# Remove symlinks from /usr/local/bin
SYMLINKS=(
    "/usr/local/bin/thermal"
    "/usr/local/bin/thermal-control"
    "/usr/local/bin/thermal-update"
    "/usr/local/bin/thermal-diagnose"
)

REMOVED_SYMLINKS=0
for symlink in "${SYMLINKS[@]}"; do
    if [ -L "$symlink" ] || [ -f "$symlink" ]; then
        sudo rm -f "$symlink"
        echo -e "${GREEN}  ✓ Removed: $symlink${NC}"
        ((REMOVED_SYMLINKS++))
    fi
done

if [ $REMOVED_SYMLINKS -eq 0 ]; then
    echo -e "${BLUE}  ℹ No symlinks found${NC}"
else
    echo -e "${GREEN}✓ Removed $REMOVED_SYMLINKS symlink(s)${NC}"
fi

echo ""
echo -e "${GREEN}[4/10]${NC} Cleaning up old installation artifacts..."

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
echo -e "${GREEN}[5/10]${NC} Searching for installations in other locations..."

# Search for thermal-management-system directories in common locations
SEARCH_PATHS=(
    "/home/*/thermal-management-system"
    "/home/*/thermal-manager"
    "/opt/thermal-management-system"
    "/opt/thermal-manager"
    "/usr/local/thermal-management-system"
    "/usr/local/thermal-manager"
    "/root/thermal-management-system"
    "/root/thermal-manager"
)

FOUND_DIRS=0
for pattern in "${SEARCH_PATHS[@]}"; do
    for dir in $pattern; do
        # Check if path exists and is not the current installation
        if [ -d "$dir" ] && [ "$(realpath "$dir" 2>/dev/null)" != "$(realpath "$SCRIPT_DIR" 2>/dev/null)" ]; then
            FOUND_DIRS=$((FOUND_DIRS + 1))
            DIR_SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
            echo -e "${YELLOW}  Found: ${dir} (${DIR_SIZE})${NC}"

            if [ "$FULL_REMOVE" = true ]; then
                sudo rm -rf "$dir"
                echo -e "${GREEN}    ✓ Removed${NC}"
            else
                read -p "    Remove this directory? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    sudo rm -rf "$dir"
                    echo -e "${GREEN}    ✓ Removed${NC}"
                else
                    echo -e "${BLUE}    ℹ Preserved${NC}"
                fi
            fi
        fi
    done
done

if [ $FOUND_DIRS -eq 0 ]; then
    echo -e "${BLUE}  ℹ No other installations found${NC}"
fi

echo ""
echo -e "${GREEN}[6/10]${NC} Searching for stray thermal manager files..."

# Search for thermal_manager.py files in common locations (excluding current dir)
STRAY_FILES_FOUND=0

# Search in common home directories
for user_home in /home/* /root; do
    if [ -d "$user_home" ]; then
        # Find thermal_manager.py files
        while IFS= read -r file; do
            # Skip if it's in the current installation directory
            if [[ "$file" != "$SCRIPT_DIR"* ]]; then
                STRAY_FILES_FOUND=$((STRAY_FILES_FOUND + 1))
                echo -e "${YELLOW}  Found: ${file}${NC}"

                if [ "$FULL_REMOVE" = true ]; then
                    sudo rm -f "$file"
                    echo -e "${GREEN}    ✓ Removed${NC}"
                else
                    read -p "    Remove this file? (y/N): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        sudo rm -f "$file"
                        echo -e "${GREEN}    ✓ Removed${NC}"
                    else
                        echo -e "${BLUE}    ℹ Preserved${NC}"
                    fi
                fi
            fi
        done < <(find "$user_home" -maxdepth 3 -name "thermal_manager.py" 2>/dev/null)
    fi
done

if [ $STRAY_FILES_FOUND -eq 0 ]; then
    echo -e "${BLUE}  ℹ No stray thermal manager files found${NC}"
fi

echo ""
echo -e "${GREEN}[7/10]${NC} Handling log directory..."

# Check new log directory
if [ -d "/var/log/thermal-manager" ]; then
    echo -e "${YELLOW}  Log directory found: /var/log/thermal-manager${NC}"

    # Show log size
    LOG_SIZE=$(du -sh /var/log/thermal-manager 2>/dev/null | cut -f1)
    echo -e "${BLUE}  Size: ${LOG_SIZE}${NC}"

    if [ "$FULL_REMOVE" = true ]; then
        sudo rm -rf /var/log/thermal-manager
        echo -e "${GREEN}  ✓ Log directory removed${NC}"
    else
        read -p "  Remove log files? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo rm -rf /var/log/thermal-manager
            echo -e "${GREEN}  ✓ Log directory removed${NC}"
        else
            echo -e "${BLUE}  ℹ Log directory preserved${NC}"
        fi
    fi
else
    echo -e "${BLUE}ℹ No log directory found${NC}"
fi

echo ""
echo -e "${GREEN}[8/10]${NC} Checking for running processes..."

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
echo -e "${GREEN}[9/10]${NC} Removing temporary files..."

# Remove override file
if [ -f "/tmp/thermal_override" ]; then
    sudo rm -f /tmp/thermal_override
    echo -e "${GREEN}  ✓ Removed thermal override file${NC}"
else
    echo -e "${BLUE}  ℹ No override file found${NC}"
fi

echo ""
echo -e "${GREEN}[10/10]${NC} Current installation directory..."

echo -e "${YELLOW}  Current directory: ${SCRIPT_DIR}${NC}"

# Show directory size
DIR_SIZE=$(du -sh "$SCRIPT_DIR" 2>/dev/null | cut -f1)
echo -e "${BLUE}  Size: ${DIR_SIZE}${NC}"

# Count files
FILE_COUNT=$(find "$SCRIPT_DIR" -type f 2>/dev/null | wc -l)
echo -e "${BLUE}  Files: ${FILE_COUNT}${NC}"

REMOVE_DIR=false
if [ "$FULL_REMOVE" = true ]; then
    REMOVE_DIR=true
    echo -e "${YELLOW}  ⚠ Full removal mode - directory will be deleted${NC}"
else
    echo ""
    echo -e "${YELLOW}  This includes ALL files:${NC}"
    echo "    - Python scripts"
    echo "    - Shell scripts"
    echo "    - Documentation"
    echo "    - .git directory and all git history"
    echo "    - Any local modifications"
    echo ""
    read -p "  Remove installation directory? (Y/n): " -n 1 -r
    echo
    # Default to yes (Y/n instead of y/N)
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        REMOVE_DIR=true
    fi
fi

if [ "$REMOVE_DIR" = true ]; then
    # Move out of the directory before removing it
    cd /tmp

    echo -e "${YELLOW}  ⚠ Removing ${SCRIPT_DIR}...${NC}"
    sudo rm -rf "$SCRIPT_DIR"
    echo -e "${GREEN}  ✓ Installation directory removed (all files deleted)${NC}"
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Uninstall Complete! ✓                         ║${NC}"
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo ""
    echo -e "${BLUE}The thermal management system has been completely removed.${NC}"
    echo -e "${BLUE}All files including git repository have been deleted.${NC}"
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
    echo -e "${YELLOW}To remove directory later: rm -rf ${SCRIPT_DIR}${NC}"
fi

echo ""
echo -e "${GREEN}Summary of what was removed:${NC}"
echo "  ✓ Systemd service (${SERVICE_NAME}.service)"
echo "  ✓ Service configuration files"
echo "  ✓ Old installation artifacts"
if [ $FOUND_DIRS -gt 0 ]; then
    echo "  ✓ Found and handled ${FOUND_DIRS} installation(s) in other locations"
fi
if [ $STRAY_FILES_FOUND -gt 0 ]; then
    echo "  ✓ Found and handled ${STRAY_FILES_FOUND} stray thermal manager file(s)"
fi
if [ "$REMOVE_DIR" = true ]; then
    echo "  ✓ Current installation directory (all files including git)"
    echo "  ✓ Log files"
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
