# Thermal Management System

**Automatic CPU-based heating system for remote equipment in cold weather environments**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![Platform: Linux](https://img.shields.io/badge/platform-Linux-lightgrey.svg)](https://www.kernel.org/)

## Overview

This thermal management system automatically monitors ambient temperature and uses CPU heating to prevent freezing damage to sensitive electronics deployed in cold weather environments. Originally designed for Meshtastic LoRa radios in remote tower installations, it can protect any equipment vulnerable to sub-freezing temperatures.

### Key Features

- **Automatic Temperature Monitoring** - Checks ACPI (ambient case) temperature every 10 seconds
- **Smart CPU Heating** - Uses controlled CPU load to generate heat when needed
- **Power Efficient** - 70% CPU utilization leaves headroom for other applications
- **Terminal GUI Dashboard** - Real-time monitoring and manual controls via Textual TUI
- **Systemd Integration** - Runs as a service, auto-starts on boot
- **Configurable Thresholds** - Customize heating triggers for your environment
- **Low Power Consumption** - Designed for PoE-powered edge devices (~18-24W total)

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/IceNet-01/thermal-management-system.git
cd thermal-management-system

# Install dependencies
sudo apt-get update
sudo apt-get install -y python3-pip
pip3 install textual --break-system-packages

# Make scripts executable
chmod +x *.py *.sh thermal

# Install and start service
./thermal_control.sh install
```

### Usage

```bash
# Launch GUI dashboard
./thermal

# Check service status
./thermal_control.sh status

# View logs
./thermal_control.sh logs

# Restart service
./thermal_control.sh restart
```

## How It Works

1. **Temperature Monitoring**: Reads ACPI thermal sensor (case ambient temperature, not CPU)
2. **Threshold Detection**: When temp drops below 0°C (32°F), heating activates
3. **CPU Heat Generation**: Spawns worker processes on all CPU cores running intensive calculations
4. **Power Management**: Each worker uses 70% CPU (work 0.7s, sleep 0.3s) leaving headroom for applications
5. **Automatic Shutdown**: When temp reaches 5°C (41°F), heating stops (hysteresis prevents rapid cycling)

### Why ACPI Instead of CPU Temperature?

- CPU self-heats, providing false "warm" readings
- ACPI measures actual case/ambient temperature
- Protects all components (radios, storage, batteries), not just CPU

## System Architecture

```
┌─────────────────────────────────────────────────────┐
│           thermal-manager.service                   │
│         (systemd background service)                │
└──────────────────┬──────────────────────────────────┘
                   │
         ┌─────────▼─────────┐
         │  thermal_manager.py │
         │  - Monitor ACPI temp │
         │  - Control heating   │
         │  - Log activity      │
         └─────────┬───────────┘
                   │
     ┌─────────────┼─────────────┐
     │             │             │
┌────▼───┐   ┌────▼───┐   ┌────▼───┐
│ Worker │   │ Worker │...│ Worker │
│ Core 0 │   │ Core 1 │   │ Core N │
└────────┘   └────────┘   └────────┘
   (CPU Heating when active)

        ┌──────────────────┐
        │ thermal_dashboard.py │  (Optional GUI)
        │ - Monitor status     │
        │ - Manual controls    │
        └──────────────────┘
```

## Configuration

Edit `thermal_manager.py` to customize:

```python
TEMP_MIN_C = 0          # Start heating below this (°C)
TEMP_TARGET_C = 5       # Stop heating above this (°C)
CHECK_INTERVAL = 10     # Temperature check interval (seconds)
CPU_USAGE = 0.70        # CPU utilization when heating (0-1)
```

## Dashboard Features

The Textual-based GUI provides:

- **Real-time temperature display** (ACPI + CPU)
- **Service status monitoring**
- **Live activity log**
- **Manual heating controls** (force on/off)
- **Service management** (restart, view logs)
- **Scrollable interface** for any terminal size

### Keyboard Shortcuts

- `q` - Quit dashboard
- `r` - Refresh all data
- `h` - Toggle heating on/off
- `s` - Restart service
- `↑/↓` - Scroll panels

## Performance

**Test Results** (Zima Board, ambient 17°C):
- **Temperature increase**: +17°C (30°F) at 100% CPU
- **Plateau time**: ~12 minutes
- **Stable temp**: 32-34°C under sustained load
- **Power consumption**: ~18-24W total system

**Expected Real-World Performance**:
- Outside ambient: -2°C (28°F)
- Case temp with heating: ~7-10°C (45-50°F)
- Safety margin: 9-12°C above freezing

## Deployment Environment

Originally designed for:
- **Platform**: Zima board (x86 SBC)
- **Power**: 12V 2A PoE adapter
- **Location**: 20ft tower installation
- **Housing**: Weather-sealed Pelican case
- **Protected equipment**: Meshtastic LoRa radios, storage
- **Environment**: North Dakota winters (-20°C to 0°C)

## File Structure

```
thermal-management-system/
├── thermal_manager.py          # Main service daemon
├── thermal_dashboard.py        # GUI dashboard (Textual)
├── thermal-manager.service     # Systemd unit file
├── thermal_control.sh          # Service management script
├── thermal                     # Dashboard launcher
├── cpu_stress.py              # Stress testing tool
├── temp_monitor.sh            # Temperature monitor script
├── heater_export.sh           # Export/backup tool
├── THERMAL_DASHBOARD.txt      # Dashboard user guide
├── HEATER_QUICK_REFERENCE.txt # Quick reference card
└── README.md                  # This file
```

## Requirements

- **OS**: Linux with systemd
- **Python**: 3.8+
- **Packages**: `textual` (for GUI)
- **Permissions**: sudo access for service installation
- **Hardware**: Thermal sensors at `/sys/class/thermal/`

## Use Cases

- **Remote radio installations** (Meshtastic, LoRa, amateur radio)
- **Edge computing devices** in outdoor enclosures
- **Weather stations** and environmental sensors
- **Security cameras** in cold climates
- **IoT devices** in unheated locations
- **Any equipment** vulnerable to freezing temperatures

## Troubleshooting

### Service won't start
```bash
sudo journalctl -u thermal-manager.service -n 50
```

### Temperatures show 0.0°C
- Check thermal sensor permissions
- Verify `/sys/class/thermal/thermal_zone*/temp` exists
- Run service as root

### Heating not activating
- Check actual temperature vs threshold
- Look for manual override file: `/tmp/thermal_override`
- Review logs: `./thermal_control.sh logs`

### GUI not launching
```bash
pip3 install textual --break-system-packages --upgrade
```

## Transfer to Another System

```bash
# Export project
./heater_export.sh

# Transfer to new system
scp heater_project_*.tar.gz user@newhost:~

# On new system
tar -xzf heater_project_*.tar.gz
cd heater_project
./INSTALL.sh
```

## Contributing

Contributions welcome! Please feel free to submit issues or pull requests.

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Built for Meshtastic mesh network deployments
- Uses [Textual](https://github.com/Textualize/textual) for the TUI dashboard
- Inspired by real-world cold weather deployment challenges

## Tags

`#thermal-management` `#cold-weather` `#iot` `#edge-computing` `#meshtastic` `#lora` `#remote-monitoring` `#systemd` `#python` `#tui`

---

**Designed and tested for remote equipment protection in harsh environments.**

For detailed technical documentation, see `HEATER_QUICK_REFERENCE.txt`
