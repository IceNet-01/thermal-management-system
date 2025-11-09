#!/usr/bin/env python3
"""
Thermal Management Service for Cold Weather Deployments
Monitors temperature and generates CPU heat when below freezing
"""

import os
import time
import multiprocessing
import signal
import sys
from datetime import datetime

# Configuration
TEMP_MIN_C = 0          # Start heating below 32°F (0°C)
TEMP_TARGET_C = 5       # Stop heating above 41°F (5°C) - hysteresis
CHECK_INTERVAL = 10     # Check temperature every 10 seconds
CPU_USAGE = 0.70        # Use 70% of available CPU for heating (leave 30% headroom)
LOG_FILE = os.environ.get("LOG_FILE", "/var/log/thermal-manager/thermal_manager.log")
OVERRIDE_FILE = "/tmp/thermal_override"  # Manual override file

# Global flag for worker processes
heating_active = multiprocessing.Value('i', 0)


def log(message):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_msg = f"[{timestamp}] {message}"
    print(log_msg)
    try:
        # Ensure log directory exists
        log_dir = os.path.dirname(LOG_FILE)
        if log_dir and not os.path.exists(log_dir):
            os.makedirs(log_dir, mode=0o755, exist_ok=True)

        with open(LOG_FILE, 'a') as f:
            f.write(log_msg + "\n")
    except Exception as e:
        print(f"Warning: Could not write to log file {LOG_FILE}: {e}")


def check_manual_override():
    """Check if manual override is active
    Returns: (override_active, force_heating_on)
    """
    try:
        if os.path.exists(OVERRIDE_FILE):
            with open(OVERRIDE_FILE, 'r') as f:
                command = f.read().strip()
                if command == "HEATING_ON":
                    return True, True
                elif command == "HEATING_OFF":
                    return True, False
    except:
        pass
    return False, False


def get_ambient_temp():
    """Read ambient/ACPI temperature (not CPU temp - we want case temperature)"""
    # Prefer ACPI thermal zone (zone0 = acpitz on Zima board)
    # This measures actual case ambient, not CPU self-heating

    # First try to get ACPI temp specifically
    acpi_zones = [
        ('/sys/class/thermal/thermal_zone0/temp', '/sys/class/thermal/thermal_zone0/type'),
    ]

    for temp_file, type_file in acpi_zones:
        try:
            # Check if this is the ACPI zone
            with open(type_file, 'r') as f:
                zone_type = f.read().strip()

            if 'acpi' in zone_type.lower():
                with open(temp_file, 'r') as f:
                    temp_millidegrees = int(f.read().strip())
                    return temp_millidegrees / 1000.0, f"ACPI ({zone_type})"
        except (FileNotFoundError, ValueError, PermissionError):
            continue

    # Fallback: read all thermal zones and use minimum (coldest = ambient)
    temps = []
    for i in range(5):  # Check up to 5 thermal zones
        try:
            temp_file = f'/sys/class/thermal/thermal_zone{i}/temp'
            type_file = f'/sys/class/thermal/thermal_zone{i}/type'

            with open(temp_file, 'r') as f:
                temp_millidegrees = int(f.read().strip())
                temp_celsius = temp_millidegrees / 1000.0

            try:
                with open(type_file, 'r') as f:
                    zone_type = f.read().strip()
            except:
                zone_type = f"zone{i}"

            temps.append((temp_celsius, zone_type))
        except (FileNotFoundError, ValueError, PermissionError):
            continue

    if temps:
        # Return coldest reading (closest to ambient)
        coldest = min(temps, key=lambda x: x[0])
        return coldest[0], coldest[1]

    return None, None


def heat_worker(worker_id, heating_flag, cpu_usage):
    """Worker process that generates CPU heat"""
    # Set process name for easier identification
    try:
        import setproctitle
        setproctitle.setproctitle(f"thermal_heater_{worker_id}")
    except ImportError:
        pass

    # Calculate work/sleep cycle for target CPU usage
    work_time = cpu_usage  # seconds of work
    sleep_time = 1 - cpu_usage  # seconds of sleep

    while True:
        if heating_flag.value:
            # Do CPU-intensive work
            start = time.time()
            result = 0
            # Simple CPU-intensive calculation
            while time.time() - start < work_time:
                result += sum(i * i for i in range(1000))

            # Sleep to achieve target CPU usage
            if sleep_time > 0:
                time.sleep(sleep_time)
        else:
            # Not heating - just sleep
            time.sleep(1)


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    log("Received shutdown signal, cleaning up...")
    heating_active.value = 0
    time.sleep(1)
    sys.exit(0)


def main():
    """Main monitoring loop"""
    log("=== Thermal Manager Starting ===")
    log(f"Python version: {sys.version}")
    log(f"Log file: {LOG_FILE}")
    log(f"Config: Min temp={TEMP_MIN_C}°C, Target={TEMP_TARGET_C}°C, CPU usage={CPU_USAGE*100}%")

    # Check if we can read temperature sensors
    test_temp, test_sensor = get_ambient_temp()
    if test_temp is None:
        log("ERROR: Cannot read temperature sensors!")
        log("Please check:")
        log("  1. This service is running as root (required for sensor access)")
        log("  2. Thermal sensors exist at /sys/class/thermal/thermal_zone*/temp")
        log("  3. Permissions allow reading thermal sensor files")
        # Don't exit - continue and show error in main loop
    else:
        log(f"Temperature sensor check OK: {test_temp}°C from {test_sensor}")

    # Setup signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Determine number of CPU cores to use
    total_cores = multiprocessing.cpu_count()
    # Use all cores but they'll individually throttle to target usage
    cores_to_use = total_cores
    log(f"System has {total_cores} CPU cores, using {cores_to_use} for heating")

    # Start worker processes
    workers = []
    for i in range(cores_to_use):
        p = multiprocessing.Process(target=heat_worker, args=(i, heating_active, CPU_USAGE))
        p.daemon = True
        p.start()
        workers.append(p)

    log(f"Started {len(workers)} heating worker processes")

    # Main monitoring loop
    currently_heating = False
    sensor_name = None

    try:
        while True:
            temp, sensor = get_ambient_temp()

            if temp is None:
                log("WARNING: Could not read temperature sensor")
                time.sleep(CHECK_INTERVAL)
                continue

            # Log sensor type on first reading
            if sensor_name is None:
                sensor_name = sensor
                log(f"Using temperature sensor: {sensor_name}")

            temp_f = (temp * 9/5) + 32  # Convert to Fahrenheit for logging

            # Check for manual override first
            override_active, force_heating = check_manual_override()

            if override_active:
                # Manual override is active
                if force_heating and not currently_heating:
                    heating_active.value = 1
                    currently_heating = True
                    log(f"HEATING ON: MANUAL OVERRIDE - Temp={temp:.1f}°C ({temp_f:.1f}°F)")
                elif not force_heating and currently_heating:
                    heating_active.value = 0
                    currently_heating = False
                    log(f"HEATING OFF: MANUAL OVERRIDE - Temp={temp:.1f}°C ({temp_f:.1f}°F)")
                else:
                    # Status unchanged - log periodically
                    status = "HEATING (OVERRIDE)" if currently_heating else "IDLE (OVERRIDE)"
                    log(f"{status}: Temp={temp:.1f}°C ({temp_f:.1f}°F) [{sensor_name}]")
            else:
                # Normal temperature-based operation
                if temp < TEMP_MIN_C and not currently_heating:
                    # Too cold - start heating
                    heating_active.value = 1
                    currently_heating = True
                    log(f"HEATING ON: Temp={temp:.1f}°C ({temp_f:.1f}°F) - Below {TEMP_MIN_C}°C")

                elif temp >= TEMP_TARGET_C and currently_heating:
                    # Warm enough - stop heating
                    heating_active.value = 0
                    currently_heating = False
                    log(f"HEATING OFF: Temp={temp:.1f}°C ({temp_f:.1f}°F) - Reached {TEMP_TARGET_C}°C")

                else:
                    # Status unchanged - log periodically
                    status = "HEATING" if currently_heating else "IDLE"
                    log(f"{status}: Temp={temp:.1f}°C ({temp_f:.1f}°F) [{sensor_name}]")

            time.sleep(CHECK_INTERVAL)

    except Exception as e:
        log(f"ERROR: {e}")
        heating_active.value = 0
        raise
    finally:
        # Cleanup
        heating_active.value = 0
        for p in workers:
            p.terminate()
        log("=== Thermal Manager Stopped ===")


if __name__ == "__main__":
    main()
