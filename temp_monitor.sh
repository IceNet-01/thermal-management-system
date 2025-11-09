#!/bin/bash
# Real-time temperature monitoring

echo "=== CPU Stress Test - Temperature Monitor ==="
echo "Time           ACPI Temp    CPU Temp     Status"
echo "================================================"

start_time=$(date +%s)

while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))

    # Read temperatures
    acpi_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f", $1/1000}')
    cpu_temp=$(cat /sys/class/thermal/thermal_zone1/temp 2>/dev/null | awk '{printf "%.1f", $1/1000}')

    # Convert to Fahrenheit
    acpi_f=$(echo "$acpi_temp" | awk '{printf "%.1f", ($1 * 9/5) + 32}')
    cpu_f=$(echo "$cpu_temp" | awk '{printf "%.1f", ($1 * 9/5) + 32}')

    # Format elapsed time
    mins=$((elapsed / 60))
    secs=$((elapsed % 60))

    printf "%02d:%02d   %6s°C (%5s°F)   %6s°C (%5s°F)\n" \
        $mins $secs "$acpi_temp" "$acpi_f" "$cpu_temp" "$cpu_f"

    sleep 5
done
