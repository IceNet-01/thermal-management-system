#!/bin/bash
# Heater Project Export Script
# Tag: #heater
# Packages entire thermal management system for transfer to another machine

set -e

PROJECT_NAME="heater_project"
EXPORT_DIR="/home/mesh/${PROJECT_NAME}"
ARCHIVE_NAME="${PROJECT_NAME}_$(date +%Y%m%d_%H%M%S).tar.gz"

echo "════════════════════════════════════════════════════════"
echo "   HEATER PROJECT EXPORT - #heater"
echo "════════════════════════════════════════════════════════"
echo ""

# Create export directory
echo "[1/4] Creating export directory..."
mkdir -p "$EXPORT_DIR"

# Copy all project files
echo "[2/4] Copying project files..."
cp /home/mesh/thermal_manager.py "$EXPORT_DIR/"
cp /home/mesh/thermal-manager.service "$EXPORT_DIR/"
cp /home/mesh/thermal_control.sh "$EXPORT_DIR/"
cp /home/mesh/thermal_dashboard.py "$EXPORT_DIR/"
cp /home/mesh/thermal "$EXPORT_DIR/"
cp /home/mesh/cpu_stress.py "$EXPORT_DIR/"
cp /home/mesh/temp_monitor.sh "$EXPORT_DIR/"
cp /home/mesh/THERMAL_DASHBOARD.txt "$EXPORT_DIR/"
cp /home/mesh/HEATER_PROJECT_README.md "$EXPORT_DIR/"
cp /home/mesh/heater_export.sh "$EXPORT_DIR/"

# Create installation script for new system
echo "[3/4] Creating auto-install script..."
cat > "$EXPORT_DIR/INSTALL.sh" << 'EOF'
#!/bin/bash
# Auto-installation script for Heater Project
# Run this on the new system

set -e

echo "════════════════════════════════════════════════════════"
echo "   HEATER PROJECT INSTALLATION"
echo "════════════════════════════════════════════════════════"
echo ""

# Check for root/sudo
if [ "$EUID" -eq 0 ]; then
   echo "Please run as normal user with sudo privileges, not as root"
   exit 1
fi

# Install dependencies
echo "[1/5] Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y python3-pip -qq
pip3 install textual --break-system-packages --quiet

# Make scripts executable
echo "[2/5] Setting permissions..."
chmod +x thermal_manager.py thermal_control.sh thermal_dashboard.py thermal cpu_stress.py temp_monitor.sh heater_export.sh

# Install service
echo "[3/5] Installing systemd service..."
sudo cp thermal-manager.service /etc/systemd/system/
sudo systemctl daemon-reload

# Enable and start service
echo "[4/5] Enabling and starting service..."
sudo systemctl enable thermal-manager.service
sudo systemctl start thermal-manager.service

# Verify
echo "[5/5] Verifying installation..."
sleep 2
if systemctl is-active --quiet thermal-manager.service; then
    echo ""
    echo "✓ Installation successful!"
    echo ""
    echo "Service Status:"
    systemctl status thermal-manager.service --no-pager -l
    echo ""
    echo "Next steps:"
    echo "  - Launch GUI: ./thermal"
    echo "  - Check status: ./thermal_control.sh status"
    echo "  - View logs: ./thermal_control.sh logs"
    echo "  - Read docs: cat HEATER_PROJECT_README.md"
else
    echo ""
    echo "✗ Service failed to start. Check logs:"
    echo "  sudo journalctl -u thermal-manager.service -n 50"
fi
EOF

chmod +x "$EXPORT_DIR/INSTALL.sh"

# Create archive
echo "[4/4] Creating archive..."
cd /home/mesh
tar -czf "$ARCHIVE_NAME" "$PROJECT_NAME/"

# Cleanup
rm -rf "$EXPORT_DIR"

echo ""
echo "════════════════════════════════════════════════════════"
echo "✓ Export complete!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Archive created: /home/mesh/$ARCHIVE_NAME"
echo ""
echo "To transfer to another system:"
echo "  1. Copy archive: scp $ARCHIVE_NAME user@newhost:~"
echo "  2. On new system: tar -xzf $ARCHIVE_NAME"
echo "  3. On new system: cd $PROJECT_NAME && ./INSTALL.sh"
echo ""
echo "Archive contains:"
tar -tzf "$ARCHIVE_NAME" | head -20
echo ""
