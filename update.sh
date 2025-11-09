#!/bin/bash
#
# Thermal Management System - Easy Update Script
# Pulls latest changes from git and restarts service if needed
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

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Thermal Management System - Update Script           ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Check if this is a git repository
if [ ! -d "${SCRIPT_DIR}/.git" ]; then
    echo -e "${RED}✗ Error: Not a git repository${NC}"
    echo "  This directory was not cloned from git."
    echo "  Updates can only be pulled from git repositories."
    exit 1
fi

# Check if service is running
SERVICE_RUNNING=false
if sudo systemctl is-active --quiet ${SERVICE_NAME}.service 2>/dev/null; then
    SERVICE_RUNNING=true
    echo -e "${BLUE}ℹ Service is currently running${NC}"
fi

echo -e "${GREEN}[1/5]${NC} Checking for local changes..."
cd "${SCRIPT_DIR}"

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo -e "${YELLOW}⚠ Warning: You have local changes that are not committed${NC}"
    echo ""
    echo "Modified files:"
    git status --short
    echo ""
    read -p "Do you want to stash these changes and continue? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}  Stashing local changes...${NC}"
        git stash push -m "Auto-stash before update $(date +%Y-%m-%d_%H:%M:%S)"
        echo -e "${GREEN}  ✓ Changes stashed (restore with: git stash pop)${NC}"
    else
        echo -e "${RED}Update cancelled${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ No local changes${NC}"
fi

echo ""
echo -e "${GREEN}[2/5]${NC} Fetching latest changes from remote..."
git fetch origin

# Check if there are updates available
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")
BASE=$(git merge-base @ @{u} 2>/dev/null || echo "")

if [ -z "$REMOTE" ]; then
    echo -e "${YELLOW}⚠ Warning: No upstream branch set${NC}"
    echo "  Setting upstream to origin/$(git branch --show-current)..."
    git branch --set-upstream-to=origin/$(git branch --show-current)
    REMOTE=$(git rev-parse @{u})
fi

if [ "$LOCAL" = "$REMOTE" ]; then
    echo -e "${GREEN}✓ Already up to date!${NC}"
    echo "  You are running the latest version."
    exit 0
elif [ "$LOCAL" = "$BASE" ]; then
    echo -e "${BLUE}ℹ Updates available${NC}"

    echo ""
    echo "Recent commits:"
    git log --oneline --decorate --graph HEAD..@{u} | head -10
    echo ""
else
    echo -e "${YELLOW}⚠ Branches have diverged${NC}"
    echo "  Your local branch and remote have different commits."
    read -p "Attempt to pull anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}[3/5]${NC} Pulling updates..."
if git pull origin $(git branch --show-current); then
    echo -e "${GREEN}✓ Updates pulled successfully${NC}"
else
    echo -e "${RED}✗ Failed to pull updates${NC}"
    echo "  You may need to resolve conflicts manually."
    exit 1
fi

echo ""
echo -e "${GREEN}[4/5]${NC} Checking for new dependencies..."

# Check if we need to update Python packages
if [ -f "${SCRIPT_DIR}/requirements.txt" ]; then
    echo "  Installing from requirements.txt..."
    pip3 install -r requirements.txt --break-system-packages 2>/dev/null || \
    pip3 install -r requirements.txt --user || true
fi

# Ensure critical packages are installed
if ! python3 -c "import textual" 2>/dev/null; then
    echo "  Installing textual..."
    pip3 install textual --break-system-packages 2>/dev/null || \
    pip3 install textual --user || true
fi

echo -e "${GREEN}✓ Dependencies up to date${NC}"

echo ""
echo -e "${GREEN}[5/5]${NC} Restarting service..."

# Check if service exists and restart it
if sudo systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    # Check if service configuration needs update
    if ! sudo diff -q /etc/systemd/system/${SERVICE_NAME}.service \
                       <(sed "s|INSTALL_DIR|${SCRIPT_DIR}|g" "${SCRIPT_DIR}/thermal-manager.service") \
                       >/dev/null 2>&1; then
        echo -e "${YELLOW}  ℹ Service file has changed, updating...${NC}"

        # Regenerate service file with current paths
        cat > /tmp/${SERVICE_NAME}.service << EOF
[Unit]
Description=Thermal Management Service for Cold Weather
Documentation=https://github.com/IceNet-01/thermal-management-system
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${SCRIPT_DIR}
ExecStart=/usr/bin/python3 ${SCRIPT_DIR}/thermal_manager.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true

# Environment
Environment="PYTHONUNBUFFERED=1"
Environment="LOG_FILE=/var/log/thermal-manager/thermal_manager.log"

[Install]
WantedBy=multi-user.target
EOF
        sudo cp /tmp/${SERVICE_NAME}.service /etc/systemd/system/
        sudo rm /tmp/${SERVICE_NAME}.service
        sudo systemctl daemon-reload
        echo -e "${GREEN}  ✓ Service file updated${NC}"
    fi

    if [ "$SERVICE_RUNNING" = true ]; then
        sudo systemctl restart ${SERVICE_NAME}.service
        echo -e "${GREEN}✓ Service restarted${NC}"

        # Wait a moment and check status
        sleep 2
        if sudo systemctl is-active --quiet ${SERVICE_NAME}.service; then
            echo -e "${GREEN}✓ Service is running properly${NC}"
        else
            echo -e "${RED}✗ Service failed to start after update${NC}"
            echo "  Check logs with: sudo journalctl -u ${SERVICE_NAME} -n 50"
        fi
    else
        echo -e "${BLUE}ℹ Service was not running, not starting it${NC}"
        echo "  Start with: ./thermal_control.sh start"
    fi
else
    echo -e "${YELLOW}⚠ Service not installed${NC}"
    echo "  Run ./install.sh to install the service"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Update Complete! 🎉                       ║${NC}"
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Show current version info
if git describe --tags --always &>/dev/null; then
    VERSION=$(git describe --tags --always)
    echo -e "${BLUE}Current version:${NC} ${VERSION}"
fi
echo -e "${BLUE}Latest commit:${NC} $(git log -1 --pretty=format:'%h - %s (%ar)')"
echo ""
echo -e "${YELLOW}Quick Status Check:${NC}"
echo -e "  ${GREEN}./thermal_control.sh status${NC}   - Check service status"
echo -e "  ${GREEN}./thermal${NC}                      - Launch GUI dashboard"
echo ""
