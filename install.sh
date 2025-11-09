#!/bin/bash
#
# Thermal Management System - Easy Installation Script
# Automatically installs dependencies, sets up systemd service, and configures auto-start on reboot
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the absolute path of the installation directory
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="thermal-manager"
LOG_DIR="/var/log/thermal-manager"
LOG_FILE="${LOG_DIR}/thermal_manager.log"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Thermal Management System - Installation Script     ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Check if running with sudo
if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}⚠ Please run without sudo. The script will request elevated privileges when needed.${NC}"
    exit 1
fi

echo -e "${GREEN}[1/7]${NC} Checking system requirements..."
# Check for Python 3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python 3 not found. Installing...${NC}"
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip
else
    echo -e "${GREEN}✓ Python 3 found: $(python3 --version)${NC}"
fi

echo ""
echo -e "${GREEN}[2/7]${NC} Installing Python dependencies..."

# Install textual for dashboard (MUST be system-wide since service runs as root)
echo -e "${YELLOW}  Installing textual system-wide (for GUI dashboard)...${NC}"
if sudo python3 -c "import textual" 2>/dev/null; then
    echo -e "${GREEN}  ✓ textual already installed (system-wide)${NC}"
else
    # Try different installation methods for different distros
    if sudo pip3 install textual --break-system-packages 2>/dev/null; then
        echo -e "${GREEN}  ✓ textual installed (break-system-packages)${NC}"
    elif sudo pip3 install textual 2>/dev/null; then
        echo -e "${GREEN}  ✓ textual installed (standard)${NC}"
    else
        echo -e "${RED}  ✗ Failed to install textual${NC}"
        echo -e "${YELLOW}  Dashboard may not work, but core service will function${NC}"
    fi
fi

# Verify textual is accessible to root
if ! sudo python3 -c "import textual" 2>/dev/null; then
    echo -e "${YELLOW}  ⚠ Warning: textual not accessible to root user${NC}"
fi

# Install numpy for ambient temperature estimation (optional)
echo -e "${YELLOW}  Installing numpy system-wide (for ambient temp estimation)...${NC}"
if sudo python3 -c "import numpy" 2>/dev/null; then
    echo -e "${GREEN}  ✓ numpy already installed (system-wide)${NC}"
else
    if sudo pip3 install numpy --break-system-packages 2>/dev/null; then
        echo -e "${GREEN}  ✓ numpy installed (break-system-packages)${NC}"
    elif sudo pip3 install numpy 2>/dev/null; then
        echo -e "${GREEN}  ✓ numpy installed (standard)${NC}"
    else
        echo -e "${YELLOW}  ⚠ numpy installation failed (optional, ambient temp estimation won't work)${NC}"
    fi
fi

echo ""
echo -e "${GREEN}[3/7]${NC} Creating log directory..."
if [ ! -d "$LOG_DIR" ]; then
    sudo mkdir -p "$LOG_DIR"
    sudo chmod 755 "$LOG_DIR"
    echo -e "${GREEN}✓ Created ${LOG_DIR}${NC}"
else
    echo -e "${GREEN}✓ Log directory exists${NC}"
fi

echo ""
echo -e "${GREEN}[4/7]${NC} Making scripts executable..."
chmod +x "${INSTALL_DIR}"/*.py "${INSTALL_DIR}"/*.sh "${INSTALL_DIR}/thermal" 2>/dev/null || true
echo -e "${GREEN}✓ Scripts are now executable${NC}"

echo ""
echo -e "${GREEN}[5/7]${NC} Creating systemd service..."

# Create the systemd service file with dynamic paths
cat > /tmp/${SERVICE_NAME}.service << EOF
[Unit]
Description=Thermal Management Service for Cold Weather
Documentation=https://github.com/IceNet-01/thermal-management-system
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/thermal_manager.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true

# Environment
Environment="PYTHONUNBUFFERED=1"
Environment="LOG_FILE=${LOG_FILE}"

[Install]
WantedBy=multi-user.target
EOF

# Install the service file
sudo cp /tmp/${SERVICE_NAME}.service /etc/systemd/system/
sudo rm /tmp/${SERVICE_NAME}.service
echo -e "${GREEN}✓ Service file created at /etc/systemd/system/${SERVICE_NAME}.service${NC}"

echo ""
echo -e "${GREEN}[6/7]${NC} Enabling and starting service..."
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}.service
sudo systemctl restart ${SERVICE_NAME}.service

# Wait a moment for service to start
sleep 2

echo ""
echo -e "${GREEN}[7/8]${NC} Adding commands to PATH..."

# Create symlinks in /usr/local/bin so commands can be run from anywhere
echo -e "${YELLOW}  Creating command symlinks in /usr/local/bin...${NC}"

# thermal - GUI dashboard
sudo ln -sf "${INSTALL_DIR}/thermal" /usr/local/bin/thermal
echo -e "${GREEN}  ✓ thermal${NC}"

# thermal-control - service management
sudo ln -sf "${INSTALL_DIR}/thermal_control.sh" /usr/local/bin/thermal-control
echo -e "${GREEN}  ✓ thermal-control${NC}"

# thermal-update - update script
sudo ln -sf "${INSTALL_DIR}/update.sh" /usr/local/bin/thermal-update
echo -e "${GREEN}  ✓ thermal-update${NC}"

# thermal-diagnose - diagnostic tool
if [ -f "${INSTALL_DIR}/diagnose.sh" ]; then
    sudo ln -sf "${INSTALL_DIR}/diagnose.sh" /usr/local/bin/thermal-diagnose
    echo -e "${GREEN}  ✓ thermal-diagnose${NC}"
fi

echo -e "${GREEN}✓ Commands added to PATH - you can now run 'thermal' from anywhere!${NC}"

echo ""
echo -e "${GREEN}[8/8]${NC} Verifying installation..."

# Check if service is active
if sudo systemctl is-active --quiet ${SERVICE_NAME}.service; then
    echo -e "${GREEN}✓ Service is running!${NC}"

    # Additional health checks
    echo ""
    echo -e "${BLUE}Running health checks...${NC}"

    # Check if log file is being written
    sleep 2
    if [ -f "$LOG_FILE" ]; then
        echo -e "${GREEN}  ✓ Log file created: ${LOG_FILE}${NC}"
        echo -e "${BLUE}  Recent log entries:${NC}"
        sudo tail -3 "$LOG_FILE" | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠ Log file not yet created (may take a moment)${NC}"
    fi

    # Check for errors in systemd journal
    if sudo journalctl -u ${SERVICE_NAME}.service --since "30 seconds ago" | grep -i error >/dev/null 2>&1; then
        echo -e "${YELLOW}  ⚠ Errors detected in service logs${NC}"
        echo -e "${YELLOW}    Run: sudo journalctl -u ${SERVICE_NAME} -n 50${NC}"
    else
        echo -e "${GREEN}  ✓ No errors in service logs${NC}"
    fi

else
    echo -e "${RED}✗ Service failed to start${NC}"
    echo ""
    echo -e "${YELLOW}Diagnostics:${NC}"

    # Show service status
    echo -e "${BLUE}Service status:${NC}"
    sudo systemctl status ${SERVICE_NAME}.service --no-pager -l | head -20 | sed 's/^/  /'

    echo ""
    echo -e "${BLUE}Recent logs:${NC}"
    sudo journalctl -u ${SERVICE_NAME}.service -n 20 --no-pager | sed 's/^/  /'

    echo ""
    echo -e "${RED}Installation incomplete. Please check the errors above.${NC}"
    echo -e "${YELLOW}Common issues:${NC}"
    echo -e "  - Python packages not installed system-wide"
    echo -e "  - Thermal sensors not accessible"
    echo -e "  - Permission issues"
    echo ""
    exit 1
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Installation Complete! 🎉                     ║${NC}"
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo ""
echo -e "${BLUE}Installation Directory:${NC} ${INSTALL_DIR}"
echo -e "${BLUE}Service Name:${NC} ${SERVICE_NAME}.service"
echo -e "${BLUE}Log File:${NC} ${LOG_FILE}"
echo ""
echo -e "${YELLOW}Quick Start Commands (run from anywhere!):${NC}"
echo -e "  ${GREEN}thermal${NC}                - Launch GUI dashboard"
echo -e "  ${GREEN}thermal-control status${NC} - Check service status"
echo -e "  ${GREEN}thermal-control logs${NC}   - View logs"
echo -e "  ${GREEN}thermal-update${NC}         - Pull latest updates"
echo -e "  ${GREEN}thermal-diagnose${NC}       - Run diagnostics"
echo ""
echo -e "${BLUE}Service Management:${NC}"
echo -e "  ${GREEN}sudo systemctl status ${SERVICE_NAME}${NC}   - Check status"
echo -e "  ${GREEN}sudo systemctl restart ${SERVICE_NAME}${NC}  - Restart service"
echo -e "  ${GREEN}sudo systemctl stop ${SERVICE_NAME}${NC}     - Stop service"
echo -e "  ${GREEN}sudo journalctl -u ${SERVICE_NAME} -f${NC}  - Follow logs"
echo ""
echo -e "${GREEN}✓ Service will automatically start on system reboot${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Run ${GREEN}thermal${NC} from anywhere to open the dashboard"
echo -e "  2. Configure temperature thresholds in the GUI"
echo -e "  3. Run ${GREEN}thermal-update${NC} anytime to get latest updates"
echo ""
