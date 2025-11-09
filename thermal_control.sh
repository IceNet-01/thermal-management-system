#!/bin/bash
# Thermal Manager Control Script

case "$1" in
    install)
        echo "Installing thermal manager service..."
        sudo cp /home/mesh/thermal-manager.service /etc/systemd/system/
        sudo systemctl daemon-reload
        sudo systemctl enable thermal-manager.service
        sudo systemctl start thermal-manager.service
        echo "Service installed and started!"
        ;;

    start)
        sudo systemctl start thermal-manager.service
        echo "Service started"
        ;;

    stop)
        sudo systemctl stop thermal-manager.service
        echo "Service stopped"
        ;;

    status)
        sudo systemctl status thermal-manager.service
        ;;

    logs)
        echo "=== System logs (last 50 lines) ==="
        sudo journalctl -u thermal-manager.service -n 50
        echo ""
        echo "=== Application log ==="
        tail -50 /home/mesh/thermal_manager.log 2>/dev/null || echo "No log file yet"
        ;;

    uninstall)
        echo "Uninstalling thermal manager service..."
        sudo systemctl stop thermal-manager.service
        sudo systemctl disable thermal-manager.service
        sudo rm /etc/systemd/system/thermal-manager.service
        sudo systemctl daemon-reload
        echo "Service uninstalled"
        ;;

    test)
        echo "Running thermal manager in foreground (Ctrl+C to stop)..."
        sudo python3 /home/mesh/thermal_manager.py
        ;;

    *)
        echo "Thermal Manager Control"
        echo "Usage: $0 {install|start|stop|status|logs|uninstall|test}"
        echo ""
        echo "  install   - Install and start as a systemd service"
        echo "  start     - Start the service"
        echo "  stop      - Stop the service"
        echo "  status    - Check service status"
        echo "  logs      - View recent logs"
        echo "  uninstall - Remove the service"
        echo "  test      - Run in foreground for testing"
        exit 1
        ;;
esac
