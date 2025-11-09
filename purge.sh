#!/bin/bash
#
# Thermal Management System - Complete System Purge Tool
#
# This tool performs a comprehensive system-wide cleanup of ALL thermal
# management files, services, and artifacts. Designed to be run BEFORE
# a fresh installation to ensure a completely clean system.
#
# Usage:
#   ./purge.sh              - Interactive mode with confirmations
#   ./purge.sh --auto       - Automatic mode (removes everything found)
#   ./purge.sh --dry-run    - Show what would be removed (no changes)
#
# This script can be run from ANY location - it doesn't need to be in
# an installation directory. Download it standalone before installing.
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SERVICE_NAME="thermal-manager"

# Parse arguments
AUTO_MODE=false
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --auto|-a)
            AUTO_MODE=true
            ;;
        --dry-run|-d)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Thermal Management System - System Purge Tool"
            echo ""
            echo "Usage:"
            echo "  $0              Interactive mode (asks before removing)"
            echo "  $0 --auto       Automatic mode (removes everything)"
            echo "  $0 --dry-run    Show what would be removed (no changes)"
            echo "  $0 --help       Show this help message"
            echo ""
            echo "This tool searches the entire system for thermal management"
            echo "installations and removes them. Use before fresh install."
            exit 0
            ;;
    esac
done

echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Thermal Management System - System Purge Tool        ║${NC}"
echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}⚠ DRY RUN MODE - No changes will be made${NC}"
    echo -e "${YELLOW}  This will show what would be removed${NC}"
    echo ""
elif [ "$AUTO_MODE" = true ]; then
    echo -e "${RED}⚠ AUTOMATIC MODE - Everything will be removed${NC}"
    echo ""
    read -p "Are you SURE you want to purge all thermal management files? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Purge cancelled${NC}"
        exit 0
    fi
else
    echo -e "${YELLOW}⚠ INTERACTIVE MODE - Will ask before removing each item${NC}"
    echo ""
    echo "This tool will search your entire system for:"
    echo "  - Thermal management installations"
    echo "  - Service files"
    echo "  - Log files"
    echo "  - Configuration files"
    echo "  - Stray thermal manager files"
    echo ""
    read -p "Continue with system scan? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Purge cancelled${NC}"
        exit 0
    fi
fi

# Tracking variables
TOTAL_REMOVED=0
TOTAL_SIZE_REMOVED=0

# Function to remove item (respects dry-run and modes)
remove_item() {
    local item="$1"
    local type="$2"  # file, directory, service

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}    [DRY RUN] Would remove${NC}"
        return 0
    fi

    if [ "$AUTO_MODE" = false ]; then
        read -p "    Remove this ${type}? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}    ℹ Preserved${NC}"
            return 0
        fi
    fi

    # Actually remove the item
    if [ -d "$item" ]; then
        sudo rm -rf "$item"
    elif [ -f "$item" ]; then
        sudo rm -f "$item"
    fi

    echo -e "${GREEN}    ✓ Removed${NC}"
    TOTAL_REMOVED=$((TOTAL_REMOVED + 1))
}

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 1: System Services                              ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Check and stop service
if sudo systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    echo -e "${YELLOW}Found: ${SERVICE_NAME}.service${NC}"

    if [ "$DRY_RUN" = false ]; then
        if sudo systemctl is-active --quiet ${SERVICE_NAME}.service 2>/dev/null; then
            sudo systemctl stop ${SERVICE_NAME}.service
            echo -e "${GREEN}  ✓ Service stopped${NC}"
        fi

        sudo systemctl disable ${SERVICE_NAME}.service 2>/dev/null || true
        echo -e "${GREEN}  ✓ Service disabled${NC}"

        if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
            remove_item "/etc/systemd/system/${SERVICE_NAME}.service" "service"
        fi

        sudo systemctl daemon-reload
        sudo systemctl reset-failed 2>/dev/null || true
    else
        echo -e "${YELLOW}  [DRY RUN] Would stop, disable, and remove service${NC}"
    fi
else
    echo -e "${BLUE}ℹ No systemd service found${NC}"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 2: Installation Directories                     ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Search patterns for installation directories
SEARCH_PATTERNS=(
    "/home/*/thermal-management-system"
    "/home/*/thermal-manager"
    "/home/*/Downloads/thermal-management-system*"
    "/opt/thermal-management-system"
    "/opt/thermal-manager"
    "/usr/local/thermal-management-system"
    "/usr/local/thermal-manager"
    "/usr/local/src/thermal-management-system"
    "/root/thermal-management-system"
    "/root/thermal-manager"
    "/tmp/thermal-management-system*"
    "/var/tmp/thermal-management-system*"
)

FOUND_DIRS=0
for pattern in "${SEARCH_PATTERNS[@]}"; do
    for dir in $pattern; do
        if [ -d "$dir" ]; then
            FOUND_DIRS=$((FOUND_DIRS + 1))
            DIR_SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
            echo -e "${YELLOW}Found: ${dir} (${DIR_SIZE})${NC}"
            remove_item "$dir" "directory"
        fi
    done
done

if [ $FOUND_DIRS -eq 0 ]; then
    echo -e "${BLUE}ℹ No installation directories found${NC}"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 3: Python Files                                 ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Search for thermal_manager.py files system-wide
PYTHON_FILES_FOUND=0

echo -e "${CYAN}Searching for thermal_manager.py files...${NC}"
for search_root in /home/* /root /opt /usr/local; do
    if [ -d "$search_root" ]; then
        while IFS= read -r file; do
            PYTHON_FILES_FOUND=$((PYTHON_FILES_FOUND + 1))
            echo -e "${YELLOW}Found: ${file}${NC}"
            remove_item "$file" "file"
        done < <(find "$search_root" -maxdepth 5 -name "thermal_manager.py" 2>/dev/null)
    fi
done

if [ $PYTHON_FILES_FOUND -eq 0 ]; then
    echo -e "${BLUE}ℹ No thermal_manager.py files found${NC}"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 4: Log Files                                    ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Check main log directory
if [ -d "/var/log/thermal-manager" ]; then
    LOG_SIZE=$(du -sh /var/log/thermal-manager 2>/dev/null | cut -f1)
    echo -e "${YELLOW}Found: /var/log/thermal-manager/ (${LOG_SIZE})${NC}"
    remove_item "/var/log/thermal-manager" "directory"
fi

# Check old log locations
OLD_LOG_LOCATIONS=(
    "/home/mesh/thermal_manager.log"
    "/home/pi/thermal_manager.log"
    "/root/thermal_manager.log"
    "/tmp/thermal_manager.log"
    "/var/tmp/thermal_manager.log"
)

LOGS_FOUND=0
for log_file in "${OLD_LOG_LOCATIONS[@]}"; do
    if [ -f "$log_file" ]; then
        LOGS_FOUND=$((LOGS_FOUND + 1))
        LOG_SIZE=$(du -sh "$log_file" 2>/dev/null | cut -f1)
        echo -e "${YELLOW}Found: ${log_file} (${LOG_SIZE})${NC}"
        remove_item "$log_file" "file"
    fi
done

if [ ! -d "/var/log/thermal-manager" ] && [ $LOGS_FOUND -eq 0 ]; then
    echo -e "${BLUE}ℹ No log files found${NC}"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 5: Service Configuration Files                  ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Old service file locations
OLD_SERVICE_LOCATIONS=(
    "/home/mesh/thermal-manager.service"
    "/home/pi/thermal-manager.service"
    "/root/thermal-manager.service"
)

SERVICES_FOUND=0
for service_file in "${OLD_SERVICE_LOCATIONS[@]}"; do
    if [ -f "$service_file" ]; then
        SERVICES_FOUND=$((SERVICES_FOUND + 1))
        echo -e "${YELLOW}Found: ${service_file}${NC}"
        remove_item "$service_file" "file"
    fi
done

if [ $SERVICES_FOUND -eq 0 ]; then
    echo -e "${BLUE}ℹ No old service files found${NC}"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 6: Running Processes                            ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Find and kill thermal processes
HEATER_PIDS=$(ps aux | grep -E "thermal_heater|thermal_manager|thermal_dashboard" | grep -v grep | grep -v "purge.sh" | awk '{print $2}')

if [ -n "$HEATER_PIDS" ]; then
    echo -e "${YELLOW}Found running processes:${NC}"
    ps aux | grep -E "thermal_heater|thermal_manager|thermal_dashboard" | grep -v grep | grep -v "purge.sh"

    if [ "$DRY_RUN" = false ]; then
        echo "$HEATER_PIDS" | while read pid; do
            if [ "$AUTO_MODE" = false ]; then
                read -p "  Kill process $pid? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    sudo kill -9 $pid 2>/dev/null || true
                    echo -e "${GREEN}  ✓ Killed process $pid${NC}"
                fi
            else
                sudo kill -9 $pid 2>/dev/null || true
                echo -e "${GREEN}  ✓ Killed process $pid${NC}"
            fi
        done
    else
        echo -e "${YELLOW}  [DRY RUN] Would kill these processes${NC}"
    fi
else
    echo -e "${BLUE}ℹ No running thermal processes found${NC}"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 7: Git Repositories & Downloads                 ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Search for git clones in common locations
GIT_REPOS_FOUND=0

for user_home in /home/* /root; do
    if [ -d "$user_home" ]; then
        # Check common git locations
        for potential_dir in "$user_home/thermal-management-system" "$user_home/Downloads/thermal-management-system" "$user_home/src/thermal-management-system" "$user_home/git/thermal-management-system"; do
            if [ -d "$potential_dir/.git" ]; then
                GIT_REPOS_FOUND=$((GIT_REPOS_FOUND + 1))
                DIR_SIZE=$(du -sh "$potential_dir" 2>/dev/null | cut -f1)
                echo -e "${YELLOW}Found git repo: ${potential_dir} (${DIR_SIZE})${NC}"
                remove_item "$potential_dir" "directory"
            fi
        done
    fi
done

if [ $GIT_REPOS_FOUND -eq 0 ]; then
    echo -e "${BLUE}ℹ No git repositories found${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
if [ "$DRY_RUN" = true ]; then
    echo -e "${GREEN}║          Dry Run Complete! ✓                           ║${NC}"
else
    echo -e "${GREEN}║          System Purge Complete! ✓                      ║${NC}"
fi
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo ""

# Summary
if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}Summary (Dry Run):${NC}"
    echo "  - Found ${FOUND_DIRS} installation director(ies)"
    echo "  - Found ${PYTHON_FILES_FOUND} Python file(s)"
    echo "  - Found ${GIT_REPOS_FOUND} git repositor(ies)"
    echo ""
    echo -e "${YELLOW}No changes were made. Run without --dry-run to remove items.${NC}"
else
    echo -e "${BLUE}Summary:${NC}"
    echo "  - Items processed: Installation dirs, Python files, logs, services"
    echo "  - Total items removed: ${TOTAL_REMOVED}"
    echo ""

    if [ $TOTAL_REMOVED -gt 0 ]; then
        echo -e "${GREEN}✓ System has been purged of thermal management files${NC}"
        echo -e "${GREEN}✓ Ready for a fresh installation${NC}"
    else
        echo -e "${BLUE}ℹ No thermal management files were found on this system${NC}"
    fi
fi

echo ""

# Final verification
if [ "$DRY_RUN" = false ]; then
    if ! sudo systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service" 2>/dev/null; then
        echo -e "${GREEN}✓ Verified: No thermal-manager service remains${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Service file may still exist${NC}"
    fi
fi

echo ""
echo -e "${CYAN}Purge tool completed. You can now perform a fresh installation.${NC}"
echo ""
