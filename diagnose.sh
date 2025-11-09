#!/bin/bash
#
# Thermal Management System - Diagnostic Tool
# Checks system configuration and identifies issues
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="thermal-manager"
LOG_FILE="/var/log/thermal-manager/thermal_manager.log"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Thermal Management System - Diagnostics             ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Check 1: Python
echo -e "${BLUE}[1] Checking Python installation...${NC}"
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    echo -e "${GREEN}✓ Python 3 installed: ${PYTHON_VERSION}${NC}"
else
    echo -e "${RED}✗ Python 3 not found${NC}"
    echo -e "${YELLOW}  Install with: sudo apt-get install python3${NC}"
fi

# Check 2: Python packages (as root - how the service runs)
echo ""
echo -e "${BLUE}[2] Checking Python packages (as root)...${NC}"

if sudo python3 -c "import textual" 2>/dev/null; then
    TEXTUAL_VERSION=$(sudo python3 -c "import textual; print(textual.__version__)" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓ textual installed (${TEXTUAL_VERSION})${NC}"
else
    echo -e "${RED}✗ textual not accessible to root${NC}"
    echo -e "${YELLOW}  Install with: sudo pip3 install textual${NC}"
fi

if sudo python3 -c "import numpy" 2>/dev/null; then
    echo -e "${GREEN}✓ numpy installed (optional)${NC}"
else
    echo -e "${YELLOW}⚠ numpy not installed (optional, for ambient temp estimation)${NC}"
fi

# Check 3: Thermal sensors
echo ""
echo -e "${BLUE}[3] Checking thermal sensors...${NC}"

SENSOR_COUNT=0
for i in {0..5}; do
    TEMP_FILE="/sys/class/thermal/thermal_zone${i}/temp"
    TYPE_FILE="/sys/class/thermal/thermal_zone${i}/type"

    if [ -f "$TEMP_FILE" ]; then
        SENSOR_COUNT=$((SENSOR_COUNT + 1))
        if [ -r "$TEMP_FILE" ]; then
            TEMP=$(cat "$TEMP_FILE" 2>/dev/null)
            TEMP_C=$((TEMP / 1000))
            TYPE=$(cat "$TYPE_FILE" 2>/dev/null || echo "unknown")
            echo -e "${GREEN}  ✓ thermal_zone${i}: ${TEMP_C}°C (${TYPE})${NC}"
        else
            echo -e "${RED}  ✗ thermal_zone${i}: Not readable (permission denied)${NC}"
        fi
    fi
done

if [ $SENSOR_COUNT -eq 0 ]; then
    echo -e "${RED}✗ No thermal sensors found${NC}"
    echo -e "${YELLOW}  This system may not have accessible thermal sensors${NC}"
else
    echo -e "${GREEN}  Found ${SENSOR_COUNT} thermal sensor(s)${NC}"
fi

# Check 4: Log directory
echo ""
echo -e "${BLUE}[4] Checking log directory...${NC}"

if [ -d "/var/log/thermal-manager" ]; then
    echo -e "${GREEN}✓ Log directory exists: /var/log/thermal-manager${NC}"

    if [ -w "/var/log/thermal-manager" ]; then
        echo -e "${GREEN}  ✓ Directory is writable${NC}"
    else
        echo -e "${YELLOW}  ⚠ Directory not writable by current user (OK if service runs as root)${NC}"
    fi

    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(du -h "$LOG_FILE" 2>/dev/null | cut -f1)
        echo -e "${GREEN}  ✓ Log file exists (${LOG_SIZE})${NC}"
    else
        echo -e "${YELLOW}  ⚠ Log file doesn't exist yet${NC}"
    fi
else
    echo -e "${RED}✗ Log directory doesn't exist${NC}"
    echo -e "${YELLOW}  Create with: sudo mkdir -p /var/log/thermal-manager${NC}"
fi

# Check 5: Service status
echo ""
echo -e "${BLUE}[5] Checking systemd service...${NC}"

if sudo systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    echo -e "${GREEN}✓ Service file installed${NC}"

    if sudo systemctl is-enabled --quiet ${SERVICE_NAME}.service 2>/dev/null; then
        echo -e "${GREEN}  ✓ Service is enabled (auto-start on boot)${NC}"
    else
        echo -e "${YELLOW}  ⚠ Service is not enabled${NC}"
        echo -e "${YELLOW}    Enable with: sudo systemctl enable ${SERVICE_NAME}${NC}"
    fi

    if sudo systemctl is-active --quiet ${SERVICE_NAME}.service; then
        echo -e "${GREEN}  ✓ Service is running${NC}"

        # Show recent activity
        echo ""
        echo -e "${BLUE}  Recent service output:${NC}"
        sudo journalctl -u ${SERVICE_NAME}.service -n 5 --no-pager | sed 's/^/    /'
    else
        echo -e "${RED}  ✗ Service is not running${NC}"

        # Show why it failed
        echo ""
        echo -e "${BLUE}  Service status:${NC}"
        sudo systemctl status ${SERVICE_NAME}.service --no-pager -l | head -15 | sed 's/^/    /'

        echo ""
        echo -e "${BLUE}  Recent error logs:${NC}"
        sudo journalctl -u ${SERVICE_NAME}.service -n 10 --no-pager | sed 's/^/    /'
    fi
else
    echo -e "${RED}✗ Service not installed${NC}"
    echo -e "${YELLOW}  Install with: ./install.sh${NC}"
fi

# Check 6: Installation files
echo ""
echo -e "${BLUE}[6] Checking installation files...${NC}"

REQUIRED_FILES=(
    "thermal_manager.py"
    "install.sh"
    "update.sh"
    "uninstall.sh"
    "thermal_control.sh"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "${SCRIPT_DIR}/${file}" ]; then
        if [ -x "${SCRIPT_DIR}/${file}" ]; then
            echo -e "${GREEN}  ✓ ${file} (executable)${NC}"
        else
            echo -e "${YELLOW}  ⚠ ${file} (not executable)${NC}"
            echo -e "${YELLOW}    Fix with: chmod +x ${SCRIPT_DIR}/${file}${NC}"
        fi
    else
        echo -e "${RED}  ✗ ${file} missing${NC}"
    fi
done

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Diagnostic Summary                                   ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Determine overall status
ISSUES=0

if ! command -v python3 &> /dev/null; then
    ((ISSUES++))
fi

if ! sudo python3 -c "import textual" 2>/dev/null; then
    ((ISSUES++))
fi

if [ $SENSOR_COUNT -eq 0 ]; then
    ((ISSUES++))
fi

if ! sudo systemctl is-active --quiet ${SERVICE_NAME}.service 2>/dev/null; then
    ((ISSUES++))
fi

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓ System appears healthy!${NC}"
    echo ""
    echo -e "${YELLOW}Quick commands:${NC}"
    echo -e "  ${GREEN}./thermal${NC}                  - Launch dashboard"
    echo -e "  ${GREEN}./thermal_control.sh status${NC}   - Check service status"
    echo -e "  ${GREEN}./thermal_control.sh logs${NC}     - View logs"
else
    echo -e "${RED}✗ Found ${ISSUES} issue(s) that need attention${NC}"
    echo ""
    echo -e "${YELLOW}Recommended actions:${NC}"

    if ! command -v python3 &> /dev/null; then
        echo -e "  1. Install Python 3: ${GREEN}sudo apt-get install python3${NC}"
    fi

    if ! sudo python3 -c "import textual" 2>/dev/null; then
        echo -e "  2. Install textual: ${GREEN}sudo pip3 install textual${NC}"
    fi

    if ! sudo systemctl is-active --quiet ${SERVICE_NAME}.service 2>/dev/null; then
        echo -e "  3. Check service logs: ${GREEN}sudo journalctl -u ${SERVICE_NAME} -n 50${NC}"
    fi

    echo ""
    echo -e "  Or try reinstalling: ${GREEN}./install.sh${NC}"
fi

echo ""
