# Ambient Temperature Estimation

**Estimate ambient air temperature using only CPU temperature and power consumption data**

---

## Overview

This module enables your thermal management system to estimate the ambient (room/environment) temperature without requiring a dedicated ambient temperature sensor. It uses a thermal physics model combined with calibration data to achieve ±2-4°C accuracy on passively-cooled SBCs like the ZimaBoard.

### How It Works

The estimator uses the thermal resistance model:

```
T_amb_est = T_cpu - (P × R_th + b)
```

**Where:**
- `T_cpu` = Current CPU package temperature (°C)
- `P` = Current power consumption (W)
- `R_th` = Thermal resistance (°C/W) — **calibrated parameter**
- `b` = Bias term (°C) — **calibrated parameter**

**Physical Interpretation:**
- The CPU temperature equals ambient plus self-heating
- Self-heating depends on power dissipation and thermal resistance
- By measuring both factors, we can work backwards to find ambient

---

## Features

### ✓ Core Functionality

- **Calibration Mode**: Collect samples and compute thermal parameters via linear regression
- **Estimation Mode**: Real-time ambient temperature estimation with uncertainty bounds
- **Persistent Storage**: Calibration data saved to JSON (survives reboots)
- **Multi-method Power Sensing**: Supports psutil, RAPL interface, and fallback estimates

### ✓ Advanced Features

- **Cold Start Detection**: Auto-adjust bias when system boots from cold state
- **Cooldown Curve Fitting**: Determine thermal time constant and validate calibration
- **Timestamped Logging**: Optional log file for trend analysis
- **Uncertainty Estimation**: Reports ±σ confidence intervals

---

## Quick Start

### 1. Installation

**Dependencies:**
```bash
# Required for calibration and advanced features
pip3 install numpy --break-system-packages

# Optional: Better power consumption estimates
pip3 install psutil --break-system-packages
```

**Files:**
- `ambient_temp_estimator.py` — Core module
- `ambient_temp_example.py` — Example usage and CLI tool

### 2. Calibration

Calibration is **required once** before estimation. Collect 5-10 samples at different CPU loads and ambient temperatures.

**Interactive Calibration:**
```bash
python3 ambient_temp_example.py --calibrate
```

**What you'll need:**
- An accurate thermometer or weather station
- 15-30 minutes
- Ability to vary CPU load (idle, moderate, heavy)

**Calibration Process:**
1. Read CPU temp and power (automatic)
2. Measure actual ambient temperature with thermometer
3. Enter ambient temp when prompted
4. Repeat at different loads (idle, 50%, 100% CPU)
5. Script computes R_th and b via linear regression

**Example session:**
```
--- Sample #1 ---
CPU Temperature: 28.5°C
Power Consumption: 7.2W
Enter measured ambient temperature (°C): 22.0
✓ Sample recorded

--- Sample #2 ---
CPU Temperature: 45.3°C
Power Consumption: 21.5W
Enter measured ambient temperature (°C): 22.0
✓ Sample recorded

[... collect 3-5 more samples ...]

✓ Calibration successful!

Results:
  R_th (Thermal Resistance): 0.9250 °C/W
  b (Bias):                  2.4500 °C
  σ (Uncertainty):           ±2.10 °C
  R² (Fit Quality):          0.9845
```

**Calibration saved to:** `/var/lib/thermal-manager/ambient_calibration.json`

---

### 3. Estimation (Real-Time)

Once calibrated, estimate ambient temperature anytime:

**Single Reading:**
```bash
python3 ambient_temp_example.py --estimate
```

**Output:**
```
Current Readings:
  CPU Temperature: 35.2°C
  Power Consumption: 12.5W

  Estimated Ambient: 21.5 ± 2.1°C
  (In Fahrenheit: 70.7 ± 3.8°F)
```

**Continuous Monitoring (5 minutes):**
```bash
python3 ambient_temp_example.py --monitor --duration 300 --interval 10
```

**Output:**
```
Timestamp            T_cpu (°C)   Power (W)    T_amb_est (°C)  Uncertainty
--------------------------------------------------------------------------------
2024-11-09 14:30:00  34.50        11.20        20.85           ±2.10°C
2024-11-09 14:30:10  35.10        12.30        21.02           ±2.10°C
2024-11-09 14:30:20  36.00        14.50        21.30           ±2.10°C
...
```

---

## Integration with Thermal Manager

### Option 1: Import as Module

```python
from ambient_temp_estimator import AmbientTempEstimator, get_cpu_temperature, get_power_consumption

# Initialize estimator (loads calibration automatically)
estimator = AmbientTempEstimator()

# Check if calibrated
if estimator.calibrated:
    # Read sensors
    T_cpu = get_cpu_temperature()
    P = get_power_consumption()

    # Estimate ambient
    T_amb_est, uncertainty = estimator.estimate(T_cpu, P)

    print(f"Ambient: {T_amb_est:.1f} ± {uncertainty:.1f}°C")
else:
    print("Estimator not calibrated. Run calibration first.")
```

### Option 2: Add to thermal_manager.py

Add ambient estimation to the main monitoring loop:

```python
# At top of thermal_manager.py
from ambient_temp_estimator import AmbientTempEstimator, get_power_consumption

# In main() function
estimator = AmbientTempEstimator()

# In monitoring loop (alongside get_ambient_temp())
if estimator.calibrated:
    try:
        T_cpu_pkg = get_cpu_package_temp()  # Read CPU package (zone1)
        P = get_power_consumption()
        T_amb_est, uncertainty = estimator.estimate(T_cpu_pkg, P)

        log(f"Estimated Ambient: {T_amb_est:.1f}±{uncertainty:.1f}°C")
    except Exception as e:
        log(f"Ambient estimation error: {e}")
```

---

## Advanced Features

### Cold Start Detection

Automatically adjusts bias when system boots from a cold state (thermal equilibrium with ambient).

**How it works:**
- Detects uptime < 60 seconds AND power < 5W
- Assumes CPU temp ≈ ambient at startup
- Gradually adjusts bias term for better accuracy

**Enable in code:**
```python
# Instead of estimate(), use:
T_amb_est, uncertainty = estimator.estimate_with_cold_start_correction(
    T_cpu, P, uptime_seconds
)
```

**Get system uptime:**
```python
import time
with open('/proc/uptime', 'r') as f:
    uptime_seconds = float(f.read().split()[0])
```

---

### Cooldown Curve Fitting

Determine thermal time constant (τ) by monitoring temperature decay when system is idle.

**Use case:**
- Validate thermal model accuracy
- Determine how fast your system cools down
- Recalibrate ambient estimation

**Run cooldown test:**
```bash
python3 ambient_temp_example.py --cooldown
```

**Process:**
1. Heat up system (e.g., run stress test)
2. Stop all CPU-intensive tasks
3. Script monitors CPU temp every 30s for 15 minutes
4. Fits exponential decay: `T(t) = T_amb + (T₀ - T_amb) × exp(-t/τ)`

**Example output:**
```
Cooldown Curve Fitting Results
================================================================================
  Time constant (τ):        420 seconds (7.0 minutes)
  Initial temp (T₀):        52.5°C
  Measured ambient (T_amb): 22.0°C
  Fitted ambient:           21.8°C
  RMSE (fit error):         0.45°C

✓ Excellent fit! Ambient estimation error: 0.20°C
```

**Interpretation:**
- **τ ≈ 7 minutes**: System takes ~7 min to cool 63% of the way to ambient
- **Low RMSE**: Model fits data well
- **Ambient error < 2°C**: Estimation is accurate

---

## Power Consumption Methods

The estimator tries multiple methods to determine power consumption:

### Method 1: psutil (CPU Utilization)
```python
import psutil
cpu_percent = psutil.cpu_percent(interval=1)
power = idle_power + (max_power - idle_power) * (cpu_percent / 100)
```

**Default values for ZimaBoard:**
- Idle power: 7W
- Max power: 22W

**Accuracy:** ±15-20%

---

### Method 2: RAPL Interface (Intel/AMD)

Reads hardware energy counter at `/sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj`

```python
# Read energy before
E1 = read_rapl_energy()
time.sleep(0.1)  # 100ms
E2 = read_rapl_energy()

# Power = ΔE / Δt
P = (E2 - E1) / 0.1
```

**Accuracy:** ±5-10% (hardware-based)

---

### Method 3: Fallback Estimate

Returns 12W (midpoint of typical SBC range)

**Use when:**
- psutil not installed
- RAPL interface not available (ARM boards)

---

## Calibration Best Practices

### Sample Collection Strategy

**Good calibration:**
- 5-10 samples
- Wide range of CPU loads (0-100%)
- Multiple ambient temperatures (if available)
- System stabilized 2-3 minutes between samples
- Accurate ambient measurement (±0.5°C thermometer)

**Example sampling plan:**

| Sample | CPU Load | Stabilization | Ambient Measurement |
|--------|----------|---------------|---------------------|
| 1      | Idle (0-5%) | 3 min | Place thermometer near intake |
| 2      | Light (25%) | 3 min | Same location |
| 3      | Moderate (50%) | 3 min | Same location |
| 4      | Heavy (75%) | 3 min | Same location |
| 5      | Max (100%) | 5 min | Same location |

**Tips:**
- Use `stress-ng` or `yes > /dev/null` to generate CPU load
- Place thermometer at board air intake (not near hot CPU)
- Avoid direct sunlight on thermometer
- If possible, vary actual ambient (morning vs. afternoon)

---

### Interpreting Calibration Results

**R² (Coefficient of Determination):**
- **> 0.95**: Excellent fit, thermal model valid
- **0.85 - 0.95**: Good fit, acceptable accuracy
- **< 0.85**: Poor fit, check sample quality or add more samples

**σ (Standard Error / Uncertainty):**
- **< 2°C**: Excellent accuracy
- **2-4°C**: Good accuracy (typical for this method)
- **> 4°C**: Poor accuracy, recalibrate with more samples

**R_th (Thermal Resistance):**
- **Typical range**: 0.5 - 2.0 °C/W for passively-cooled SBCs
- **ZimaBoard**: ~0.8 - 1.2 °C/W
- **Higher value** = poorer heat dissipation (smaller heatsink)

**b (Bias):**
- **Typical range**: 0 - 5°C
- Accounts for sensor offsets and model imperfections

---

## Troubleshooting

### Problem: "Estimator must be calibrated before estimation"

**Solution:**
```bash
python3 ambient_temp_example.py --calibrate
```

---

### Problem: "NumPy not available"

**Solution:**
```bash
pip3 install numpy --break-system-packages
```

---

### Problem: "Could not read CPU temperature"

**Cause:** CPU thermal zone not at expected path

**Solution:** Find correct thermal zone
```bash
# List all thermal zones
for i in {0..9}; do
    if [ -f /sys/class/thermal/thermal_zone$i/temp ]; then
        echo -n "Zone $i: "
        cat /sys/class/thermal/thermal_zone$i/type
        echo -n "  Temp: "
        cat /sys/class/thermal/thermal_zone$i/temp
    fi
done
```

Edit `ambient_temp_estimator.py` line ~370 to use correct zone:
```python
cpu_zones = [
    '/sys/class/thermal/thermal_zone2/temp',  # Change to your CPU zone
]
```

---

### Problem: Estimated ambient is always too high/low

**Cause:** Calibration drift or bias error

**Solutions:**

1. **Recalibrate** with fresh samples
2. **Use cold start correction:**
   ```python
   estimator.estimate_with_cold_start_correction(T_cpu, P, uptime)
   ```
3. **Manual bias adjustment:**
   ```python
   estimator.b += 2.0  # Add 2°C to bias
   estimator.save_calibration()
   ```

---

### Problem: Large uncertainty (σ > 5°C)

**Causes:**
- Poor calibration samples (noisy data)
- Model doesn't fit hardware well
- Power consumption estimates inaccurate

**Solutions:**

1. **Recalibrate** with more samples (8-10)
2. **Use hardware power sensor** if available
3. **Verify CPU thermal zone** is correct (package, not core)
4. **Check sample quality:**
   ```bash
   python3 ambient_temp_example.py --calibrate
   # Look at "Error" column in validation table
   # Errors should be < 3°C per sample
   ```

---

## File Locations

| File | Purpose | Location |
|------|---------|----------|
| Calibration data | JSON config | `/var/lib/thermal-manager/ambient_calibration.json` |
| Estimation logs | Timestamped estimates | `/var/log/thermal-manager/ambient_estimates.log` |
| Module | Python library | `./ambient_temp_estimator.py` |
| Examples | CLI tool | `./ambient_temp_example.py` |

**Permissions:**
- Calibration directory: Requires write access to `/var/lib/thermal-manager/`
- Log directory: Requires write access to `/var/log/thermal-manager/`

**Create directories:**
```bash
sudo mkdir -p /var/lib/thermal-manager /var/log/thermal-manager
sudo chown $USER:$USER /var/lib/thermal-manager /var/log/thermal-manager
```

Or use local directory:
```python
# In code:
estimator = AmbientTempEstimator(config_file="./ambient_calibration.json")
```

---

## API Reference

### Class: `AmbientTempEstimator`

#### `__init__(config_file: str)`
Initialize estimator and load calibration if available.

#### `calibrate(samples: List[Tuple[float, float, float]]) -> Dict`
Perform calibration using sample data.
- **Input:** `[(T_cpu, P, T_amb), ...]`
- **Returns:** `{R_th, b, sigma, r_squared, n_samples}`

#### `estimate(T_cpu: float, P: float) -> Tuple[float, float]`
Estimate ambient temperature.
- **Returns:** `(T_amb_est, uncertainty)`

#### `estimate_with_cold_start_correction(T_cpu, P, uptime) -> Tuple[float, float]`
Estimate with automatic bias adjustment on cold boot.

#### `fit_cooldown_curve(time_series, T_amb_measured) -> Dict`
Fit exponential decay curve to temperature data.
- **Input:** `[(time_sec, T_cpu), ...]`
- **Returns:** `{tau, T_amb_fitted, T_0, rmse}`

#### `save_calibration() -> None`
Save calibration to JSON file.

#### `load_calibration() -> bool`
Load calibration from JSON file.

---

### Utility Functions

#### `get_cpu_temperature() -> float`
Read CPU package temperature from sysfs.

#### `get_power_consumption() -> float`
Estimate system power consumption (tries psutil → RAPL → fallback).

#### `log_estimation(T_amb_est, uncertainty, T_cpu, P, log_file)`
Append timestamped estimation to log file.

---

## Theory & Validation

### Thermal Resistance Model

For a passively-cooled device at steady state:

```
Q = P                           (Heat generated = Power dissipated)
Q = (T_cpu - T_amb) / R_th      (Thermal resistance equation)

Rearranging:
T_cpu - T_amb = P × R_th

Including sensor bias:
T_cpu - T_amb = P × R_th + b
```

**Assumptions:**
- Steady-state thermal equilibrium (no rapid transients)
- Linear thermal resistance (valid for passive cooling)
- Constant ambient temperature during measurement

---

### Expected Accuracy

**Best case (good calibration, stable conditions):**
- ±2-3°C accuracy
- R² > 0.95

**Typical case:**
- ±3-4°C accuracy
- R² ≈ 0.90

**Factors affecting accuracy:**
- Calibration sample quality
- Power consumption measurement error
- Thermal transients (system heating/cooling)
- Changing fan speeds (if active cooling)
- Thermal coupling to other heat sources

---

### Validation Methods

1. **Cross-validation during calibration**
   - Check prediction errors in calibration output
   - All errors should be < 3°C

2. **Cooldown curve test**
   - Fitted ambient should match measured ambient within 2°C
   - RMSE < 1°C indicates excellent model fit

3. **Long-term monitoring**
   - Compare estimated ambient to weather station data
   - Should track ambient temperature changes

4. **Side-by-side comparison**
   - Place thermometer near device
   - Compare estimated vs. measured over 1 hour
   - Mean error should be < 3°C

---

## Performance Impact

**CPU overhead:** Negligible
- Estimation: Single arithmetic operation
- Power reading (psutil): ~1ms
- Temperature reading (sysfs): <1ms

**Memory usage:** <100KB
- Calibration data: ~1KB JSON file
- Module footprint: ~50KB

**Disk I/O:**
- Calibration save: Once per calibration
- Log append: Optional, ~50 bytes/reading

**Network:** None

**Suitable for:** Embedded systems, continuous monitoring (1-10 second intervals)

---

## License

MIT License - See LICENSE file

---

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review calibration quality (R², σ)
3. Verify sensor paths (`/sys/class/thermal/`)
4. Test with example script: `python3 ambient_temp_example.py --calibrate-example`

---

## Changelog

**v1.0.0** (2024-11-09)
- Initial release
- Calibration via linear regression
- Real-time estimation with uncertainty
- Cold start detection
- Cooldown curve fitting
- Persistent JSON storage
- Multi-method power consumption sensing
- Example CLI tool with monitoring mode
