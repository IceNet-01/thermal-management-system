#!/bin/bash
#
# Test Manual Override Functionality
# This script tests if the thermal manager responds to manual override commands
#

OVERRIDE_FILE="/tmp/thermal_override"
LOG_FILE="/var/log/thermal-manager/thermal_manager.log"

echo "=== Manual Override Test ==="
echo ""

# Test 1: Create override file
echo "[Test 1] Creating manual override file..."
echo "HEATING_ON" > "$OVERRIDE_FILE"
chmod 644 "$OVERRIDE_FILE"

echo "  Override file created:"
ls -la "$OVERRIDE_FILE"
echo "  Contents: $(cat $OVERRIDE_FILE)"
echo ""

# Test 2: Check if service can read it
echo "[Test 2] Checking file permissions..."
if [ -r "$OVERRIDE_FILE" ]; then
    echo "  ✓ File is readable"
else
    echo "  ✗ File is NOT readable"
fi
echo ""

# Test 3: Watch logs for response
echo "[Test 3] Watching logs for 15 seconds..."
echo "  (Looking for 'MANUAL OVERRIDE' in logs)"
echo "  Press Ctrl+C to stop early"
echo ""

timeout 15 tail -f "$LOG_FILE" 2>/dev/null | grep --line-buffered -i "override\|heating" &
TAIL_PID=$!

sleep 15
kill $TAIL_PID 2>/dev/null

echo ""
echo "[Test 4] Checking last 5 log entries..."
sudo tail -5 "$LOG_FILE" 2>/dev/null || echo "  Cannot read log file (permission denied)"

echo ""
echo "[Test 5] Cleaning up..."
rm -f "$OVERRIDE_FILE"
echo "  ✓ Override file removed"

echo ""
echo "=== Test Complete ==="
echo ""
echo "If you saw 'HEATING ON: MANUAL OVERRIDE' in the logs, the test PASSED"
echo "If not, the service may need to be restarted: sudo systemctl restart thermal-manager.service"
