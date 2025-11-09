#!/usr/bin/env python3
"""
Ambient Temperature Estimator for Passively-Cooled SBCs

This module estimates ambient air temperature using CPU temperature and power
consumption data, based on the thermal model:

    T_amb_est = T_cpu - (P * R_th + b)

Where:
    T_cpu = current CPU temperature (°C)
    P = current power consumption (W)
    R_th = thermal resistance (°C/W) [calibrated]
    b = bias term (°C) [calibrated]

Features:
- Calibration mode: Compute R_th and b via linear regression
- Estimation mode: Real-time ambient temperature estimation
- Uncertainty estimation: ±σ confidence intervals
- Persistent storage: JSON-based calibration data
- Cold start detection: Auto-update bias on system startup
- Cooldown curve fitting: Optional recalibration method

Author: Thermal Management System
License: MIT
"""

import json
import os
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import warnings

try:
    import numpy as np
    NUMPY_AVAILABLE = True
except ImportError:
    NUMPY_AVAILABLE = False
    warnings.warn("NumPy not available. Install with: pip3 install numpy")


class AmbientTempEstimator:
    """
    Estimates ambient temperature using CPU temperature and power consumption.

    Attributes:
        R_th (float): Thermal resistance in °C/W
        b (float): Bias term in °C
        sigma (float): Standard error of estimation (uncertainty)
        calibrated (bool): Whether the estimator has been calibrated
        calibration_time (str): Timestamp of last calibration
        n_samples (int): Number of calibration samples used
    """

    def __init__(self, config_file: str = "/var/lib/thermal-manager/ambient_calibration.json"):
        """
        Initialize the ambient temperature estimator.

        Args:
            config_file: Path to calibration data file
        """
        self.config_file = config_file
        self.R_th = None
        self.b = None
        self.sigma = 3.0  # Default uncertainty ±3°C
        self.calibrated = False
        self.calibration_time = None
        self.n_samples = 0

        # Cold start detection parameters
        self.cold_start_threshold = 300  # 5 minutes offline = cold start
        self.last_shutdown_time = None

        # Cooldown curve parameters
        self.tau = None  # Time constant for exponential decay

        # Ensure config directory exists
        os.makedirs(os.path.dirname(self.config_file), exist_ok=True)

        # Load existing calibration if available
        self.load_calibration()

    def calibrate(self, samples: List[Tuple[float, float, float]]) -> Dict[str, float]:
        """
        Calibrate the estimator using measured data samples.

        Uses linear regression to compute R_th and b from the thermal model:
            T_cpu - T_amb = P * R_th + b

        Args:
            samples: List of (T_cpu, P, T_amb_measured) tuples
                T_cpu: CPU temperature in °C
                P: Power consumption in W
                T_amb_measured: Measured ambient temperature in °C

        Returns:
            Dictionary with calibration results:
                - R_th: Thermal resistance (°C/W)
                - b: Bias term (°C)
                - sigma: Standard error (°C)
                - r_squared: Coefficient of determination
                - n_samples: Number of samples used

        Raises:
            ValueError: If insufficient samples or invalid data
            ImportError: If NumPy is not available
        """
        if not NUMPY_AVAILABLE:
            raise ImportError("NumPy is required for calibration. Install with: pip3 install numpy")

        if len(samples) < 3:
            raise ValueError(f"Need at least 3 samples for calibration, got {len(samples)}")

        # Extract data
        T_cpu = np.array([s[0] for s in samples])
        P = np.array([s[1] for s in samples])
        T_amb = np.array([s[2] for s in samples])

        # Validate data
        if np.any(np.isnan(T_cpu)) or np.any(np.isnan(P)) or np.any(np.isnan(T_amb)):
            raise ValueError("Sample data contains NaN values")

        if np.any(P <= 0):
            raise ValueError("Power consumption must be positive")

        # Compute temperature delta (dependent variable)
        delta_T = T_cpu - T_amb

        # Linear regression: delta_T = R_th * P + b
        # Using least squares: [P, 1] @ [R_th, b] = delta_T
        X = np.column_stack([P, np.ones(len(P))])
        coeffs, residuals, rank, s = np.linalg.lstsq(X, delta_T, rcond=None)

        self.R_th = coeffs[0]
        self.b = coeffs[1]

        # Compute uncertainty (standard error)
        predictions = X @ coeffs
        errors = delta_T - predictions
        self.sigma = np.std(errors)

        # Compute R² (coefficient of determination)
        ss_res = np.sum(errors ** 2)
        ss_tot = np.sum((delta_T - np.mean(delta_T)) ** 2)
        r_squared = 1 - (ss_res / ss_tot) if ss_tot > 0 else 0.0

        # Update metadata
        self.calibrated = True
        self.calibration_time = datetime.now().isoformat()
        self.n_samples = len(samples)

        # Save calibration
        self.save_calibration()

        return {
            'R_th': float(self.R_th),
            'b': float(self.b),
            'sigma': float(self.sigma),
            'r_squared': float(r_squared),
            'n_samples': self.n_samples,
            'calibration_time': self.calibration_time
        }

    def estimate(self, T_cpu: float, P: float) -> Tuple[float, float]:
        """
        Estimate ambient temperature from current CPU temp and power consumption.

        Args:
            T_cpu: Current CPU temperature in °C
            P: Current power consumption in W

        Returns:
            Tuple of (T_amb_est, uncertainty):
                T_amb_est: Estimated ambient temperature in °C
                uncertainty: Uncertainty in °C (±σ)

        Raises:
            ValueError: If estimator not calibrated or invalid inputs
        """
        if not self.calibrated:
            raise ValueError("Estimator must be calibrated before estimation")

        if np.isnan(T_cpu) or np.isnan(P):
            raise ValueError("Invalid input: T_cpu or P is NaN")

        if P < 0:
            raise ValueError("Power consumption must be non-negative")

        # Apply thermal model: T_amb = T_cpu - (P * R_th + b)
        T_amb_est = T_cpu - (P * self.R_th + self.b)

        return T_amb_est, self.sigma

    def estimate_with_cold_start_correction(self, T_cpu: float, P: float,
                                           uptime_seconds: float) -> Tuple[float, float]:
        """
        Estimate ambient temperature with cold start detection and correction.

        If the system was off long enough to reach thermal equilibrium (cold start),
        the initial CPU temperature should be close to ambient, allowing bias adjustment.

        Args:
            T_cpu: Current CPU temperature in °C
            P: Current power consumption in W
            uptime_seconds: System uptime in seconds

        Returns:
            Tuple of (T_amb_est, uncertainty) in °C
        """
        # Detect cold start (system just booted and very low power/temp)
        if uptime_seconds < 60 and P < 5:  # First minute, low power
            # Assume CPU temp ≈ ambient during cold start
            # Update bias: b = T_cpu - T_amb, but T_amb ≈ T_cpu at startup
            # So we can adjust b to minimize initial offset
            cold_start_bias = P * self.R_th  # Expected offset from power alone
            self.b = self.b * 0.9 + cold_start_bias * 0.1  # Gradual adjustment
            self.save_calibration()

        return self.estimate(T_cpu, P)

    def fit_cooldown_curve(self, time_series: List[Tuple[float, float]],
                          T_amb_measured: float) -> Dict[str, float]:
        """
        Fit exponential cooldown curve to refine thermal model.

        When the system is powered down or idle, CPU temperature decays
        exponentially toward ambient:
            T(t) = T_amb + (T₀ - T_amb) * exp(-t/τ)

        This method fits τ (time constant) and can recalibrate T_amb.

        Args:
            time_series: List of (time_seconds, T_cpu) measurements during cooldown
            T_amb_measured: Actual measured ambient temperature

        Returns:
            Dictionary with:
                - tau: Time constant in seconds
                - T_amb_fitted: Fitted ambient temperature
                - T_0: Initial temperature at t=0
                - rmse: Root mean square error

        Raises:
            ValueError: If insufficient data or invalid inputs
            ImportError: If NumPy is not available
        """
        if not NUMPY_AVAILABLE:
            raise ImportError("NumPy required for cooldown curve fitting")

        if len(time_series) < 5:
            raise ValueError(f"Need at least 5 points for curve fitting, got {len(time_series)}")

        t = np.array([x[0] for x in time_series])
        T = np.array([x[1] for x in time_series])

        # Normalize time to start at 0
        t = t - t[0]
        T_0 = T[0]

        # Transform to linear form: ln(T - T_amb) = ln(T_0 - T_amb) - t/τ
        # Use measured T_amb
        if np.any(T <= T_amb_measured):
            raise ValueError("Temperature must be above ambient during cooldown")

        y = np.log(T - T_amb_measured)

        # Linear fit: y = a - t/τ, where a = ln(T_0 - T_amb)
        coeffs = np.polyfit(t, y, 1)
        slope = coeffs[0]
        intercept = coeffs[1]

        # Extract parameters
        self.tau = -1.0 / slope  # Time constant
        T_amb_fitted = T_0 - np.exp(intercept)  # Fitted ambient

        # Compute RMSE
        T_predicted = T_amb_measured + (T_0 - T_amb_measured) * np.exp(-t / self.tau)
        rmse = np.sqrt(np.mean((T - T_predicted) ** 2))

        return {
            'tau': float(self.tau),
            'T_amb_fitted': float(T_amb_fitted),
            'T_0': float(T_0),
            'T_amb_measured': float(T_amb_measured),
            'rmse': float(rmse)
        }

    def save_calibration(self) -> None:
        """Save calibration data to JSON file."""
        data = {
            'R_th': self.R_th,
            'b': self.b,
            'sigma': self.sigma,
            'calibrated': self.calibrated,
            'calibration_time': self.calibration_time,
            'n_samples': self.n_samples,
            'tau': self.tau
        }

        with open(self.config_file, 'w') as f:
            json.dump(data, f, indent=2)

    def load_calibration(self) -> bool:
        """
        Load calibration data from JSON file.

        Returns:
            True if calibration loaded successfully, False otherwise
        """
        if not os.path.exists(self.config_file):
            return False

        try:
            with open(self.config_file, 'r') as f:
                data = json.load(f)

            self.R_th = data.get('R_th')
            self.b = data.get('b')
            self.sigma = data.get('sigma', 3.0)
            self.calibrated = data.get('calibrated', False)
            self.calibration_time = data.get('calibration_time')
            self.n_samples = data.get('n_samples', 0)
            self.tau = data.get('tau')

            return self.calibrated
        except (json.JSONDecodeError, KeyError) as e:
            warnings.warn(f"Failed to load calibration: {e}")
            return False

    def get_calibration_info(self) -> Dict[str, any]:
        """
        Get current calibration information.

        Returns:
            Dictionary with calibration parameters and metadata
        """
        return {
            'calibrated': self.calibrated,
            'R_th': self.R_th,
            'b': self.b,
            'sigma': self.sigma,
            'calibration_time': self.calibration_time,
            'n_samples': self.n_samples,
            'tau': self.tau,
            'config_file': self.config_file
        }


def get_acpi_ambient_temperature() -> float:
    """
    Read ACPI ambient/case temperature from sysfs.

    This is the same sensor used by thermal_manager.py for ambient temperature.
    It measures the case/environment temperature, not CPU self-heating.

    Returns:
        Ambient temperature in °C

    Raises:
        IOError: If temperature cannot be read
    """
    # Try ACPI thermal zones (usually zone0 on most SBCs)
    acpi_zones = [
        ('/sys/class/thermal/thermal_zone0/temp', '/sys/class/thermal/thermal_zone0/type'),
    ]

    for temp_path, type_path in acpi_zones:
        if os.path.exists(temp_path) and os.path.exists(type_path):
            try:
                # Check if this is actually an ACPI zone
                with open(type_path, 'r') as f:
                    zone_type = f.read().strip().lower()

                if 'acpi' in zone_type:
                    with open(temp_path, 'r') as f:
                        temp_millidegrees = int(f.read().strip())
                        return temp_millidegrees / 1000.0
            except (IOError, ValueError):
                continue

    # Fallback: Just read zone0 even if type doesn't say ACPI
    if os.path.exists('/sys/class/thermal/thermal_zone0/temp'):
        try:
            with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                temp_millidegrees = int(f.read().strip())
                return temp_millidegrees / 1000.0
        except (IOError, ValueError):
            pass

    raise IOError("Could not read ACPI/ambient temperature from thermal zones")


def get_cpu_temperature() -> float:
    """
    Read CPU package temperature from sysfs.

    Returns:
        CPU temperature in °C

    Raises:
        IOError: If temperature cannot be read
    """
    # Try common thermal zones for CPU package temp
    cpu_zones = [
        '/sys/class/thermal/thermal_zone1/temp',  # Often CPU on Zima Board
        '/sys/class/thermal/thermal_zone2/temp',
        '/sys/class/thermal/thermal_zone3/temp',
    ]

    for zone in cpu_zones:
        if os.path.exists(zone):
            try:
                with open(zone, 'r') as f:
                    temp_millidegrees = int(f.read().strip())
                    return temp_millidegrees / 1000.0
            except (IOError, ValueError):
                continue

    raise IOError("Could not read CPU temperature from any thermal zone")


def get_power_consumption() -> float:
    """
    Estimate system power consumption.

    Tries multiple methods in order of preference:
    1. psutil CPU percentage → estimated power
    2. RAPL energy interface (Intel/AMD)
    3. Hardcoded estimate based on typical SBC power draw

    Returns:
        Estimated power consumption in Watts
    """
    try:
        # Method 1: Use psutil for CPU utilization-based estimate
        import psutil
        cpu_percent = psutil.cpu_percent(interval=1)

        # Typical ZimaBoard/SBC power profile:
        # - Idle: ~6-8W
        # - Load: ~18-24W
        idle_power = 7.0
        max_power = 22.0
        estimated_power = idle_power + (max_power - idle_power) * (cpu_percent / 100.0)

        return estimated_power

    except ImportError:
        pass

    try:
        # Method 2: Try RAPL interface (Intel Running Average Power Limit)
        rapl_path = '/sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj'
        if os.path.exists(rapl_path):
            # Read energy counter (microjoules)
            with open(rapl_path, 'r') as f:
                energy_1 = int(f.read().strip())

            time.sleep(0.1)  # 100ms sample

            with open(rapl_path, 'r') as f:
                energy_2 = int(f.read().strip())

            # Power = ΔE / Δt
            delta_energy_j = (energy_2 - energy_1) / 1_000_000.0
            power_w = delta_energy_j / 0.1

            return power_w

    except (IOError, ValueError):
        pass

    # Method 3: Fallback to conservative estimate
    # Return midpoint of typical SBC power range
    return 12.0


def get_weather_ambient_temperature(latitude: float = None, longitude: float = None,
                                   api_key: str = None) -> Tuple[float, str]:
    """
    Get ambient temperature from weather API.

    Tries multiple free weather services in order:
    1. weather.gov (US only, no API key needed)
    2. OpenWeatherMap (requires free API key)
    3. wttr.in (IP-based geolocation, no key needed)

    Args:
        latitude: Location latitude (optional for some services)
        longitude: Location longitude (optional for some services)
        api_key: OpenWeatherMap API key (optional)

    Returns:
        Tuple of (temperature_celsius, source_name)

    Raises:
        IOError: If unable to fetch weather data from any source
    """
    import urllib.request
    import urllib.error

    # Method 1: weather.gov (NOAA, US only, no API key)
    if latitude is not None and longitude is not None:
        try:
            # Get grid point
            url = f"https://api.weather.gov/points/{latitude:.4f},{longitude:.4f}"
            headers = {'User-Agent': 'ThermalManagementSystem/1.0'}
            req = urllib.request.Request(url, headers=headers)

            with urllib.request.urlopen(req, timeout=10) as response:
                data = json.loads(response.read().decode())
                forecast_url = data['properties']['forecastHourly']

            # Get current temperature
            req = urllib.request.Request(forecast_url, headers=headers)
            with urllib.request.urlopen(req, timeout=10) as response:
                data = json.loads(response.read().decode())
                temp_f = data['properties']['periods'][0]['temperature']
                temp_c = (temp_f - 32) * 5/9
                return temp_c, "weather.gov"
        except (urllib.error.URLError, KeyError, IndexError, ValueError):
            pass  # Try next method

    # Method 2: OpenWeatherMap (requires API key)
    if api_key and latitude is not None and longitude is not None:
        try:
            url = f"https://api.openweathermap.org/data/2.5/weather?lat={latitude}&lon={longitude}&appid={api_key}&units=metric"
            with urllib.request.urlopen(url, timeout=10) as response:
                data = json.loads(response.read().decode())
                temp_c = data['main']['temp']
                return temp_c, "OpenWeatherMap"
        except (urllib.error.URLError, KeyError, ValueError):
            pass  # Try next method

    # Method 3: wttr.in (IP-based geolocation, no config needed)
    try:
        url = "https://wttr.in/?format=%t"
        with urllib.request.urlopen(url, timeout=10) as response:
            temp_str = response.read().decode().strip()
            # Parse formats like "+15°C" or "-2°C"
            temp_str = temp_str.replace('°C', '').replace('°F', '').replace('+', '').strip()
            temp_c = float(temp_str)
            return temp_c, "wttr.in"
    except (urllib.error.URLError, ValueError):
        pass

    raise IOError("Unable to fetch weather data from any source")


def auto_calibrate_with_stress(estimator: AmbientTempEstimator,
                               ambient_source: str = "acpi",
                               latitude: float = None,
                               longitude: float = None,
                               api_key: str = None,
                               num_samples: int = 8,
                               verbose: bool = True) -> Dict[str, float]:
    """
    Automatic calibration by varying CPU load and collecting samples.

    This function automatically calibrates the estimator without requiring
    manual thermometer measurements. It:
    1. Gets ambient temperature from ACPI sensor or weather API
    2. Varies CPU load from idle to 100%
    3. Waits for thermal stabilization at each load level
    4. Collects (T_cpu, P, T_amb) samples
    5. Performs calibration via linear regression

    Args:
        estimator: AmbientTempEstimator instance to calibrate
        ambient_source: Source for ambient temp ("acpi", "weather", or "both")
        latitude: Location latitude (for weather API)
        longitude: Location longitude (for weather API)
        api_key: OpenWeatherMap API key (optional)
        num_samples: Number of calibration samples (default: 8)
        verbose: Print progress messages

    Returns:
        Calibration results dictionary

    Raises:
        ImportError: If required modules not available
        IOError: If cannot read sensors or ambient source
    """
    import subprocess
    import multiprocessing

    if not NUMPY_AVAILABLE:
        raise ImportError("NumPy required for auto-calibration")

    # Get ambient temperature reference
    T_amb_ref = None
    amb_source_name = ""

    if ambient_source in ["acpi", "both"]:
        try:
            T_amb_ref = get_acpi_ambient_temperature()
            amb_source_name = "ACPI sensor"
            if verbose:
                print(f"✓ Using ACPI ambient temperature: {T_amb_ref:.2f}°C")
        except IOError as e:
            if ambient_source == "acpi":
                raise IOError(f"Cannot read ACPI sensor: {e}")

    if ambient_source in ["weather", "both"] and T_amb_ref is None:
        try:
            T_amb_ref, source = get_weather_ambient_temperature(latitude, longitude, api_key)
            amb_source_name = f"Weather API ({source})"
            if verbose:
                print(f"✓ Using weather API ambient temperature: {T_amb_ref:.2f}°C (source: {source})")
        except IOError as e:
            if ambient_source == "weather":
                raise IOError(f"Cannot fetch weather data: {e}")

    if T_amb_ref is None:
        raise IOError("Could not obtain ambient temperature from any source")

    if verbose:
        print(f"\n{'='*70}")
        print(f"AUTO-CALIBRATION MODE")
        print(f"{'='*70}")
        print(f"Ambient reference: {T_amb_ref:.2f}°C ({amb_source_name})")
        print(f"Collecting {num_samples} samples at different CPU loads...")
        print(f"This will take ~{num_samples * 3} minutes (3 min per sample)")
        print(f"\nNote: Ambient temperature is assumed constant during calibration.")
        print(f"      For best results, run indoors or in stable conditions.")

    samples = []
    cpu_count = multiprocessing.cpu_count()

    # Define load levels (0%, 25%, 50%, 75%, 100%, and some in between)
    load_levels = [0.0, 0.15, 0.30, 0.50, 0.70, 0.85, 1.0, 0.40][:num_samples]

    for i, load in enumerate(load_levels):
        if verbose:
            print(f"\n--- Sample {i+1}/{num_samples}: CPU load {int(load*100)}% ---")

        # Apply CPU load using stress-ng or yes command
        stress_process = None
        if load > 0:
            try:
                # Try stress-ng first
                cpu_workers = max(1, int(cpu_count * load))
                stress_process = subprocess.Popen(
                    ['stress-ng', '--cpu', str(cpu_workers), '--quiet'],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
                if verbose:
                    print(f"  Applying load with stress-ng ({cpu_workers} workers)...")
            except FileNotFoundError:
                # Fallback to yes > /dev/null
                stress_process = subprocess.Popen(
                    f"yes > /dev/null & " * int(cpu_count * load),
                    shell=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
                if verbose:
                    print(f"  Applying load with shell command...")

        # Wait for thermal stabilization (3 minutes)
        stabilization_time = 180  # 3 minutes
        if verbose:
            print(f"  Waiting {stabilization_time}s for thermal stabilization...")

        for t in range(stabilization_time):
            time.sleep(1)
            if verbose and t % 30 == 0 and t > 0:
                try:
                    T_cpu_current = get_cpu_temperature()
                    print(f"    {t}s: CPU temp = {T_cpu_current:.1f}°C")
                except:
                    pass

        # Read sensors
        try:
            T_cpu = get_cpu_temperature()
            P = get_power_consumption()

            samples.append((T_cpu, P, T_amb_ref))

            if verbose:
                print(f"  ✓ Sample recorded: T_cpu={T_cpu:.2f}°C, P={P:.2f}W, T_amb={T_amb_ref:.2f}°C")

        except Exception as e:
            if verbose:
                print(f"  ✗ Error reading sensors: {e}")

        # Stop stress process
        if stress_process:
            stress_process.terminate()
            try:
                stress_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                stress_process.kill()

            # Also kill any lingering yes processes
            subprocess.run(['pkill', '-9', 'yes'], stderr=subprocess.DEVNULL)

    # Perform calibration
    if len(samples) < 3:
        raise ValueError(f"Only collected {len(samples)} samples, need at least 3")

    if verbose:
        print(f"\n{'='*70}")
        print(f"Performing calibration with {len(samples)} samples...")
        print(f"{'='*70}")

    results = estimator.calibrate(samples)

    if verbose:
        print(f"\n✓ Auto-calibration successful!")
        print(f"\nResults:")
        print(f"  R_th (Thermal Resistance): {results['R_th']:.4f} °C/W")
        print(f"  b (Bias):                  {results['b']:.4f} °C")
        print(f"  σ (Uncertainty):           ±{results['sigma']:.2f} °C")
        print(f"  R² (Fit Quality):          {results['r_squared']:.4f}")
        print(f"\n📁 Calibration saved to: {estimator.config_file}")

    return results


def log_estimation(T_amb_est: float, uncertainty: float, T_cpu: float, P: float,
                  log_file: str = "/var/log/thermal-manager/ambient_estimates.log") -> None:
    """
    Log ambient temperature estimation with timestamp.

    Args:
        T_amb_est: Estimated ambient temperature in °C
        uncertainty: Uncertainty in °C
        T_cpu: CPU temperature in °C
        P: Power consumption in W
        log_file: Path to log file
    """
    os.makedirs(os.path.dirname(log_file), exist_ok=True)

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = (f"[{timestamp}] T_amb={T_amb_est:.2f}±{uncertainty:.2f}°C "
                f"(T_cpu={T_cpu:.1f}°C, P={P:.1f}W)\n")

    with open(log_file, 'a') as f:
        f.write(log_entry)


if __name__ == "__main__":
    # Basic functionality test
    print("Ambient Temperature Estimator - Module Test")
    print("=" * 50)

    if NUMPY_AVAILABLE:
        print("✓ NumPy available")
    else:
        print("✗ NumPy not available - install for full functionality")

    try:
        T_cpu = get_cpu_temperature()
        print(f"✓ CPU Temperature: {T_cpu:.1f}°C")
    except Exception as e:
        print(f"✗ Could not read CPU temperature: {e}")

    try:
        P = get_power_consumption()
        print(f"✓ Power Consumption: {P:.1f}W")
    except Exception as e:
        print(f"✗ Could not estimate power: {e}")

    print("\nRun ambient_temp_example.py for calibration and estimation examples.")
