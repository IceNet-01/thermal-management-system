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

# Install textual for dashboard
if ! python3 -c "import textual" 2>/dev/null; then
    echo -e "${YELLOW}  Installing textual (for GUI dashboard)...${NC}"
    pip3 install textual --break-system-packages 2>/dev/null || \
    pip3 install textual --user 2>/dev/null || \
    sudo pip3 install textual
    echo -e "${GREEN}  ✓ textual installed${NC}"
else
    echo -e "${GREEN}  ✓ textual already installed${NC}"
fi

# Install numpy for ambient temperature estimation (optional)
if ! python3 -c "import numpy" 2>/dev/null; then
    echo -e "${YELLOW}  Installing numpy (for ambient temp estimation)...${NC}"
    pip3 install numpy --break-system-packages 2>/dev/null || \
    pip3 install numpy --user 2>/dev/null || \
    sudo pip3 install numpy || true
    echo -e "${GREEN}  ✓ numpy installed (optional feature)${NC}"
else
    echo -e "${GREEN}  ✓ numpy already installed${NC}"
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
echo -e "${GREEN}[7/7]${NC} Verifying installation..."
if sudo systemctl is-active --quiet ${SERVICE_NAME}.service; then
    echo -e "${GREEN}✓ Service is running!${NC}"
else
    echo -e "${RED}✗ Service failed to start. Check logs with: sudo journalctl -u ${SERVICE_NAME} -n 50${NC}"
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
echo -e "${YELLOW}Quick Start Commands:${NC}"
echo -e "  ${GREEN}./thermal${NC}              - Launch GUI dashboard"
echo -e "  ${GREEN}./thermal_control.sh status${NC}   - Check service status"
echo -e "  ${GREEN}./thermal_control.sh logs${NC}     - View logs"
echo -e "  ${GREEN}./update.sh${NC}            - Pull latest updates"
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
echo -e "  1. Run ${GREEN}./thermal${NC} to open the dashboard and monitor temperature"
echo -e "  2. Customize thresholds in ${BLUE}thermal_manager.py${NC} if needed"
echo -e "  3. Run ${GREEN}./update.sh${NC} anytime to get latest updates"
echo ""
