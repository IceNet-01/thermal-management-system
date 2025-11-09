#!/bin/bash
# Thermal Manager Control Script

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="thermal-manager"
LOG_FILE="/var/log/thermal-manager/thermal_manager.log"

case "$1" in
    install)
        echo "⚠ Please use ./install.sh for installation instead."
        echo "  The install.sh script handles dependencies and configuration automatically."
        exit 1
        ;;

    start)
        sudo systemctl start ${SERVICE_NAME}.service
        echo "✓ Service started"
        ;;

    stop)
        sudo systemctl stop ${SERVICE_NAME}.service
        echo "✓ Service stopped"
        ;;

    restart)
        sudo systemctl restart ${SERVICE_NAME}.service
        echo "✓ Service restarted"
        ;;

    status)
        sudo systemctl status ${SERVICE_NAME}.service
        ;;

    logs)
        echo "=== System logs (last 50 lines) ==="
        sudo journalctl -u ${SERVICE_NAME}.service -n 50
        echo ""
        echo "=== Application log ==="
        if [ -f "$LOG_FILE" ]; then
            tail -50 "$LOG_FILE"
        else
            echo "No log file found at $LOG_FILE"
        fi
        ;;

    follow)
        echo "Following service logs (Ctrl+C to stop)..."
        sudo journalctl -u ${SERVICE_NAME}.service -f
        ;;

    uninstall)
        echo "⚠ Please use ./uninstall.sh for complete removal instead."
        echo "  The uninstall.sh script handles:"
        echo "    - Service removal"
        echo "    - Log cleanup (with confirmation)"
        echo "    - Old installation cleanup"
        echo "    - Optional directory removal"
        echo ""
        echo "  Run: ./uninstall.sh"
        exit 1
        ;;

    test)
        echo "Running thermal manager in foreground (Ctrl+C to stop)..."
        sudo python3 "${SCRIPT_DIR}/thermal_manager.py"
        ;;

    *)
        echo "Thermal Manager Control"
        echo "Usage: $0 {start|stop|restart|status|logs|follow|test}"
        echo ""
        echo "  start     - Start the service"
        echo "  stop      - Stop the service"
        echo "  restart   - Restart the service"
        echo "  status    - Check service status"
        echo "  logs      - View recent logs"
        echo "  follow    - Follow logs in real-time"
        echo "  test      - Run in foreground for testing"
        echo ""
        echo "For installation, use: ./install.sh"
        echo "For updates, use: ./update.sh"
        echo "For removal, use: ./uninstall.sh"
        exit 1
        ;;
esac
