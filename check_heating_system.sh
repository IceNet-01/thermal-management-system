#!/bin/bash
#
# Quick diagnostic to check heating system status
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    Thermal Management System Status Check        ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

# Check service status
echo -e "${YELLOW}1. Service Status:${NC}"
if systemctl is-active --quiet thermal-manager.service 2>/dev/null; then
    echo -e "   ${GREEN}✓ Service is RUNNING${NC}"
    echo -e "   ${BLUE}→ Automatic heating based on temperature is ACTIVE${NC}"
else
    echo -e "   ${RED}✗ Service is NOT RUNNING${NC}"
    echo -e "   ${YELLOW}→ Only manual heating from GUI will work${NC}"
    echo -e "   ${YELLOW}→ To enable automatic heating, start the service${NC}"
fi
echo ""

# Check config file
echo -e "${YELLOW}2. Temperature Configuration:${NC}"
if [ -f "/tmp/thermal_config" ]; then
    echo -e "   ${GREEN}✓ Config file exists${NC}"
    cat /tmp/thermal_config | sed 's/^/   /'
else
    echo -e "   ${BLUE}ℹ Using defaults: Min=0°C, Target=5°C${NC}"
    echo -e "   ${BLUE}→ Save config from GUI to customize${NC}"
fi
echo ""

# Check current temperature
echo -e "${YELLOW}3. Current Temperature:${NC}"
if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
    TEMP_MILLIC=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$((TEMP_MILLIC / 1000))
    TEMP_F=$(((TEMP_C * 9 / 5) + 32))
    echo -e "   ${BLUE}ACPI: ${TEMP_C}°C (${TEMP_F}°F)${NC}"
else
    echo -e "   ${RED}✗ Cannot read temperature sensor${NC}"
fi
echo ""

# Check for manual workers
echo -e "${YELLOW}4. Manual Heating Workers:${NC}"
WORKER_COUNT=$(ps aux | grep -c "thermal_manual_heater" | grep -v grep || echo "0")
if [ "$WORKER_COUNT" -gt 0 ]; then
    echo -e "   ${GREEN}✓ Manual workers running: $WORKER_COUNT${NC}"
    echo -e "   ${BLUE}→ GUI manual heating is ACTIVE${NC}"
else
    echo -e "   ${BLUE}ℹ No manual workers running${NC}"
fi
echo ""

# Check log file
echo -e "${YELLOW}5. Recent Log Entries:${NC}"
if [ -f "/var/log/thermal-manager/thermal_manager.log" ]; then
    echo -e "   ${GREEN}✓ Log file exists${NC}"
    tail -3 /var/log/thermal-manager/thermal_manager.log 2>/dev/null | sed 's/^/   /' || \
        echo -e "   ${YELLOW}⚠ Cannot read log file (may need sudo)${NC}"
else
    echo -e "   ${RED}✗ Log file not found${NC}"
fi
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}How the system works:${NC}"
echo ""
echo -e "  ${GREEN}AUTOMATIC HEATING${NC} (requires service running):"
echo -e "    • Service monitors temperature every 10 seconds"
echo -e "    • Starts heating when temp < min threshold"
echo -e "    • Stops heating when temp >= target threshold"
echo -e "    • Configure thresholds in GUI"
echo ""
echo -e "  ${GREEN}MANUAL HEATING${NC} (GUI only, no service needed):"
echo -e "    • Click 'Manual ON' to force heating"
echo -e "    • Click 'Manual OFF' to stop"
echo -e "    • Works independently of temperature"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
