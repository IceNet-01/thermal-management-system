#!/usr/bin/env python3
"""
Ambient Temperature Estimation - Example Usage

This script demonstrates:
1. Calibration mode: Collecting samples and computing R_th and b
2. Estimation mode: Real-time ambient temperature estimation
3. Cold start detection: Automatic bias adjustment
4. Cooldown curve fitting: Thermal time constant determination

Usage:
    # Calibration mode
    python3 ambient_temp_example.py --calibrate

    # Estimation mode (requires prior calibration)
    python3 ambient_temp_example.py --estimate

    # Live monitoring with logging
    python3 ambient_temp_example.py --monitor --duration 300

    # Cooldown curve fitting
    python3 ambient_temp_example.py --cooldown

Author: Thermal Management System
License: MIT
"""

import argparse
import time
import sys
from datetime import datetime
from typing import List, Tuple

try:
    from ambient_temp_estimator import (
        AmbientTempEstimator,
        get_cpu_temperature,
        get_acpi_ambient_temperature,
        get_power_consumption,
        get_weather_ambient_temperature,
        auto_calibrate_with_stress,
        log_estimation
    )
except ImportError:
    print("Error: ambient_temp_estimator.py must be in the same directory")
    sys.exit(1)


def calibration_mode_interactive():
    """
    Interactive calibration mode.

    Guides the user through collecting calibration samples by prompting
    for measured ambient temperature while automatically reading CPU temp
    and power consumption.
    """
    print("\n" + "=" * 70)
    print("CALIBRATION MODE - Ambient Temperature Estimator")
    print("=" * 70)
    print("\nThis calibration will compute thermal resistance (R_th) and bias (b)")
    print("by collecting samples of CPU temperature, power, and measured ambient.")
    print("\nFor best results:")
    print("  • Collect 5-10 samples at different system loads")
    print("  • Let system stabilize 2-3 minutes between samples")
    print("  • Use an accurate thermometer for ambient measurement")
    print("  • Vary CPU load (idle, moderate, heavy)")

    estimator = AmbientTempEstimator()
    samples = []

    print("\n" + "-" * 70)
    print("Sample Collection")
    print("-" * 70)

    while True:
        print(f"\n--- Sample #{len(samples) + 1} ---")

        # Read CPU temp and power automatically
        try:
            T_cpu = get_cpu_temperature()
            P = get_power_consumption()
        except Exception as e:
            print(f"Error reading sensors: {e}")
            continue

        print(f"CPU Temperature: {T_cpu:.2f}°C")
        print(f"Power Consumption: {P:.2f}W")

        # Prompt for measured ambient temperature
        while True:
            user_input = input("Enter measured ambient temperature (°C) or 'done' to finish: ")

            if user_input.lower() == 'done':
                break

            try:
                T_amb_measured = float(user_input)
                if T_amb_measured < -50 or T_amb_measured > 60:
                    print("⚠ Temperature out of reasonable range. Try again.")
                    continue

                # Add sample
                samples.append((T_cpu, P, T_amb_measured))
                print(f"✓ Sample recorded: T_cpu={T_cpu:.2f}°C, P={P:.2f}W, T_amb={T_amb_measured:.2f}°C")
                break

            except ValueError:
                print("Invalid input. Enter a number or 'done'.")

        if user_input.lower() == 'done':
            break

        # Ask if user wants another sample
        if len(samples) >= 3:
            another = input("\nCollect another sample? (y/n): ")
            if another.lower() != 'y':
                break

    # Perform calibration
    if len(samples) < 3:
        print("\n✗ Need at least 3 samples for calibration. Exiting.")
        return

    print("\n" + "=" * 70)
    print(f"Performing calibration with {len(samples)} samples...")
    print("=" * 70)

    try:
        results = estimator.calibrate(samples)

        print("\n✓ Calibration successful!")
        print("\nResults:")
        print(f"  R_th (Thermal Resistance): {results['R_th']:.4f} °C/W")
        print(f"  b (Bias):                  {results['b']:.4f} °C")
        print(f"  σ (Uncertainty):           ±{results['sigma']:.2f} °C")
        print(f"  R² (Fit Quality):          {results['r_squared']:.4f}")
        print(f"  Samples Used:              {results['n_samples']}")
        print(f"  Calibration Time:          {results['calibration_time']}")

        print("\n📁 Calibration saved to:", estimator.config_file)

        # Show sample predictions
        print("\n" + "-" * 70)
        print("Calibration Validation - Predicted vs. Measured")
        print("-" * 70)
        print(f"{'T_cpu (°C)':<12} {'Power (W)':<12} {'Measured (°C)':<15} {'Predicted (°C)':<15} {'Error (°C)':<12}")
        print("-" * 70)

        for T_cpu, P, T_amb_measured in samples:
            T_amb_pred, _ = estimator.estimate(T_cpu, P)
            error = T_amb_pred - T_amb_measured
            print(f"{T_cpu:<12.2f} {P:<12.2f} {T_amb_measured:<15.2f} {T_amb_pred:<15.2f} {error:<12.2f}")

    except Exception as e:
        print(f"\n✗ Calibration failed: {e}")


def calibration_mode_example():
    """
    Example calibration with synthetic data.

    This demonstrates the calibration process with pre-defined samples.
    In real use, you would collect actual measurements.
    """
    print("\n" + "=" * 70)
    print("CALIBRATION MODE - Example with Synthetic Data")
    print("=" * 70)

    # Example calibration samples: (T_cpu, P, T_amb_measured)
    # Simulating a ZimaBoard at different loads and ambient temps
    samples = [
        (25.0, 7.0, 20.0),    # Idle, cool ambient
        (32.0, 12.0, 20.0),   # Moderate load, cool ambient
        (45.0, 22.0, 20.0),   # Heavy load, cool ambient
        (22.0, 7.5, 15.0),    # Idle, cold ambient
        (38.0, 15.0, 15.0),   # Moderate load, cold ambient
        (30.0, 8.0, 25.0),    # Idle, warm ambient
        (50.0, 23.0, 25.0),   # Heavy load, warm ambient
        (28.0, 9.0, 22.0),    # Light load, moderate ambient
    ]

    print(f"\nUsing {len(samples)} synthetic calibration samples:")
    print(f"{'T_cpu (°C)':<12} {'Power (W)':<12} {'T_ambient (°C)':<15}")
    print("-" * 40)
    for T_cpu, P, T_amb in samples:
        print(f"{T_cpu:<12.1f} {P:<12.1f} {T_amb:<15.1f}")

    estimator = AmbientTempEstimator()

    try:
        results = estimator.calibrate(samples)

        print("\n✓ Calibration successful!")
        print("\nResults:")
        print(f"  R_th (Thermal Resistance): {results['R_th']:.4f} °C/W")
        print(f"  b (Bias):                  {results['b']:.4f} °C")
        print(f"  σ (Uncertainty):           ±{results['sigma']:.2f} °C")
        print(f"  R² (Fit Quality):          {results['r_squared']:.4f}")

    except Exception as e:
        print(f"\n✗ Calibration failed: {e}")


def estimation_mode_single():
    """
    Single-shot estimation mode.

    Reads current CPU temp and power, estimates ambient temperature.
    """
    print("\n" + "=" * 70)
    print("ESTIMATION MODE - Single Reading")
    print("=" * 70)

    estimator = AmbientTempEstimator()

    if not estimator.calibrated:
        print("\n✗ Estimator not calibrated!")
        print("Run calibration mode first: python3 ambient_temp_example.py --calibrate")
        return

    # Show calibration info
    info = estimator.get_calibration_info()
    print(f"\n✓ Using calibration from {info['calibration_time']}")
    print(f"  R_th = {info['R_th']:.4f} °C/W")
    print(f"  b = {info['b']:.4f} °C")
    print(f"  σ = ±{info['sigma']:.2f} °C")

    # Read current sensors
    try:
        T_cpu = get_cpu_temperature()
        P = get_power_consumption()
    except Exception as e:
        print(f"\n✗ Error reading sensors: {e}")
        return

    print("\n" + "-" * 70)
    print("Current Readings:")
    print("-" * 70)
    print(f"  CPU Temperature: {T_cpu:.2f}°C")
    print(f"  Power Consumption: {P:.2f}W")

    # Estimate ambient
    try:
        T_amb_est, uncertainty = estimator.estimate(T_cpu, P)

        print("\n" + "=" * 70)
        print(f"  Estimated Ambient: {T_amb_est:.2f} ± {uncertainty:.2f}°C")
        print("=" * 70)

        # Also show in Fahrenheit
        T_amb_f = T_amb_est * 9/5 + 32
        uncertainty_f = uncertainty * 9/5
        print(f"  (In Fahrenheit: {T_amb_f:.1f} ± {uncertainty_f:.1f}°F)")

    except Exception as e:
        print(f"\n✗ Estimation failed: {e}")


def monitor_mode(duration: int = 300, interval: int = 10, enable_logging: bool = True):
    """
    Continuous monitoring mode.

    Estimates ambient temperature in real-time and optionally logs results.

    Args:
        duration: Total monitoring duration in seconds (default: 5 min)
        interval: Update interval in seconds (default: 10 sec)
        enable_logging: Whether to log estimates to file
    """
    print("\n" + "=" * 70)
    print("MONITORING MODE - Real-Time Ambient Temperature Estimation")
    print("=" * 70)

    estimator = AmbientTempEstimator()

    if not estimator.calibrated:
        print("\n✗ Estimator not calibrated!")
        print("Run calibration mode first: python3 ambient_temp_example.py --calibrate")
        return

    # Show calibration info
    info = estimator.get_calibration_info()
    print(f"\n✓ Using calibration from {info['calibration_time']}")
    print(f"  Monitoring for {duration} seconds (interval: {interval}s)")
    if enable_logging:
        print(f"  Logging to: /var/log/thermal-manager/ambient_estimates.log")

    print("\n" + "-" * 70)
    print(f"{'Timestamp':<20} {'T_cpu (°C)':<12} {'Power (W)':<12} {'T_amb_est (°C)':<15} {'Uncertainty':<12}")
    print("-" * 70)

    start_time = time.time()
    readings = []

    try:
        while time.time() - start_time < duration:
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

            # Read sensors
            try:
                T_cpu = get_cpu_temperature()
                P = get_power_consumption()
                T_amb_est, uncertainty = estimator.estimate(T_cpu, P)

                # Display
                print(f"{timestamp:<20} {T_cpu:<12.2f} {P:<12.2f} {T_amb_est:<15.2f} ±{uncertainty:.2f}°C")

                # Log if enabled
                if enable_logging:
                    log_estimation(T_amb_est, uncertainty, T_cpu, P)

                # Store for statistics
                readings.append(T_amb_est)

            except Exception as e:
                print(f"{timestamp:<20} Error: {e}")

            time.sleep(interval)

    except KeyboardInterrupt:
        print("\n\nMonitoring stopped by user (Ctrl+C)")

    # Show summary statistics
    if readings:
        import statistics
        print("\n" + "=" * 70)
        print("Summary Statistics")
        print("=" * 70)
        print(f"  Total readings: {len(readings)}")
        print(f"  Mean ambient:   {statistics.mean(readings):.2f}°C")
        print(f"  Std deviation:  {statistics.stdev(readings):.2f}°C" if len(readings) > 1 else "  Std deviation:  N/A")
        print(f"  Min ambient:    {min(readings):.2f}°C")
        print(f"  Max ambient:    {max(readings):.2f}°C")


def cooldown_mode():
    """
    Cooldown curve fitting mode.

    Monitors temperature decay when system is idle/cooling down to
    determine thermal time constant (τ) and validate ambient estimation.
    """
    print("\n" + "=" * 70)
    print("COOLDOWN CURVE FITTING MODE")
    print("=" * 70)
    print("\nThis mode fits an exponential decay curve: T(t) = T_amb + (T₀ - T_amb) * exp(-t/τ)")
    print("\nInstructions:")
    print("  1. Start from a warm system (e.g., after running stress test)")
    print("  2. Stop all CPU-intensive tasks")
    print("  3. Let the system cool naturally for 10-15 minutes")
    print("  4. This script will record temperature vs. time")

    input("\nPress Enter when ready to start monitoring cooldown...")

    estimator = AmbientTempEstimator()

    # Get measured ambient temperature
    while True:
        try:
            T_amb_measured = float(input("\nEnter measured ambient temperature (°C): "))
            if -50 < T_amb_measured < 60:
                break
            print("Temperature out of reasonable range. Try again.")
        except ValueError:
            print("Invalid input. Enter a number.")

    print(f"\n✓ Measuring cooldown curve (15 minutes, 30-second intervals)...")
    print(f"{'Time (s)':<10} {'CPU Temp (°C)':<15}")
    print("-" * 30)

    time_series = []
    start_time = time.time()
    duration = 900  # 15 minutes
    interval = 30   # 30 seconds

    try:
        while time.time() - start_time < duration:
            elapsed = time.time() - start_time
            T_cpu = get_cpu_temperature()

            print(f"{elapsed:<10.0f} {T_cpu:<15.2f}")
            time_series.append((elapsed, T_cpu))

            time.sleep(interval)

    except KeyboardInterrupt:
        print("\n\nCooldown monitoring stopped by user (Ctrl+C)")

    if len(time_series) < 5:
        print("\n✗ Need at least 5 data points for curve fitting.")
        return

    # Fit cooldown curve
    try:
        results = estimator.fit_cooldown_curve(time_series, T_amb_measured)

        print("\n" + "=" * 70)
        print("Cooldown Curve Fitting Results")
        print("=" * 70)
        print(f"  Time constant (τ):        {results['tau']:.1f} seconds ({results['tau']/60:.1f} minutes)")
        print(f"  Initial temp (T₀):        {results['T_0']:.2f}°C")
        print(f"  Measured ambient (T_amb): {results['T_amb_measured']:.2f}°C")
        print(f"  Fitted ambient:           {results['T_amb_fitted']:.2f}°C")
        print(f"  RMSE (fit error):         {results['rmse']:.2f}°C")

        # Validation
        error = abs(results['T_amb_fitted'] - results['T_amb_measured'])
        if error < 2.0:
            print(f"\n✓ Excellent fit! Ambient estimation error: {error:.2f}°C")
        elif error < 4.0:
            print(f"\n✓ Good fit. Ambient estimation error: {error:.2f}°C")
        else:
            print(f"\n⚠ Moderate fit. Ambient estimation error: {error:.2f}°C")
            print("  Consider recalibration or longer cooldown period.")

    except Exception as e:
        print(f"\n✗ Curve fitting failed: {e}")


def auto_calibration_mode(use_acpi: bool = True, use_weather: bool = False,
                         latitude: float = None, longitude: float = None,
                         api_key: str = None):
    """
    Automatic calibration mode - no thermometer required!

    Automatically calibrates by:
    1. Getting ambient temp from ACPI sensor or weather API
    2. Varying CPU load (0% to 100%)
    3. Collecting samples at each load level
    4. Computing R_th and b via regression

    Args:
        use_acpi: Use ACPI thermal sensor for ambient reference
        use_weather: Use weather API for ambient reference
        latitude: Location latitude (for weather API)
        longitude: Location longitude (for weather API)
        api_key: OpenWeatherMap API key (optional)
    """
    print("\n" + "=" * 70)
    print("AUTO-CALIBRATION MODE - No Thermometer Required!")
    print("=" * 70)
    print("\nThis mode automatically calibrates without manual measurements.")
    print("It will:")
    print("  1. Obtain ambient temperature from ACPI sensor or weather API")
    print("  2. Automatically vary CPU load from 0% to 100%")
    print("  3. Collect temperature/power samples at each load level")
    print("  4. Compute calibration constants via linear regression")
    print("\n⚠ WARNING: This will stress your CPU for ~20-30 minutes!")
    print("           Make sure:")
    print("           - Device is in a stable environment (no rapid temp changes)")
    print("           - Adequate cooling/ventilation")
    print("           - No critical tasks running")

    # Determine ambient source
    if use_weather:
        ambient_source = "weather"
    elif use_acpi:
        ambient_source = "acpi"
    else:
        ambient_source = "both"

    print(f"\nAmbient temperature source: {ambient_source}")

    # Confirm before proceeding
    response = input("\nContinue with auto-calibration? (yes/no): ")
    if response.lower() not in ['yes', 'y']:
        print("Auto-calibration cancelled.")
        return

    estimator = AmbientTempEstimator()

    try:
        # Run auto-calibration
        results = auto_calibrate_with_stress(
            estimator=estimator,
            ambient_source=ambient_source,
            latitude=latitude,
            longitude=longitude,
            api_key=api_key,
            num_samples=8,
            verbose=True
        )

        print("\n" + "=" * 70)
        print("AUTO-CALIBRATION COMPLETE!")
        print("=" * 70)
        print("\nYou can now use --estimate or --monitor to get ambient temperature")
        print("without any external thermometer.")

    except KeyboardInterrupt:
        print("\n\nAuto-calibration interrupted by user (Ctrl+C)")
        print("Partial calibration not saved.")
    except Exception as e:
        print(f"\n✗ Auto-calibration failed: {e}")
        import traceback
        traceback.print_exc()


def test_ambient_sources():
    """Test available ambient temperature sources."""
    print("\n" + "=" * 70)
    print("TESTING AMBIENT TEMPERATURE SOURCES")
    print("=" * 70)

    # Test ACPI sensor
    print("\n1. ACPI Thermal Sensor")
    print("-" * 40)
    try:
        temp = get_acpi_ambient_temperature()
        print(f"✓ ACPI sensor available")
        print(f"  Temperature: {temp:.2f}°C ({temp * 9/5 + 32:.1f}°F)")
    except Exception as e:
        print(f"✗ ACPI sensor not available: {e}")

    # Test weather API (wttr.in - no config needed)
    print("\n2. Weather API (wttr.in - IP-based)")
    print("-" * 40)
    try:
        temp, source = get_weather_ambient_temperature()
        print(f"✓ Weather API available")
        print(f"  Source: {source}")
        print(f"  Temperature: {temp:.2f}°C ({temp * 9/5 + 32:.1f}°F)")
    except Exception as e:
        print(f"✗ Weather API not available: {e}")

    # Test CPU sensor (for comparison)
    print("\n3. CPU Package Temperature (for reference)")
    print("-" * 40)
    try:
        temp = get_cpu_temperature()
        print(f"✓ CPU sensor available")
        print(f"  Temperature: {temp:.2f}°C ({temp * 9/5 + 32:.1f}°F)")
        print(f"  Note: CPU temp includes self-heating, not true ambient")
    except Exception as e:
        print(f"✗ CPU sensor not available: {e}")

    # Recommendations
    print("\n" + "=" * 70)
    print("RECOMMENDATIONS")
    print("=" * 70)
    print("\nFor auto-calibration, use:")
    print("  • ACPI sensor (--auto-calibrate) - Most accurate for local conditions")
    print("  • Weather API (--auto-calibrate-weather) - Good for verification")
    print("\nACPI sensor is preferred as it measures actual device environment.")


def main():
    """Main entry point with CLI argument parsing."""
    parser = argparse.ArgumentParser(
        description="Ambient Temperature Estimator - Calibration and Estimation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # AUTO-CALIBRATION (no thermometer required!)
  python3 ambient_temp_example.py --auto-calibrate          # Uses ACPI sensor
  python3 ambient_temp_example.py --auto-calibrate-weather  # Uses weather API
  python3 ambient_temp_example.py --test-sources            # Test what's available

  # Interactive calibration mode (requires thermometer)
  python3 ambient_temp_example.py --calibrate

  # Example calibration with synthetic data
  python3 ambient_temp_example.py --calibrate-example

  # Single ambient temperature estimate
  python3 ambient_temp_example.py --estimate

  # Monitor for 5 minutes with 10-second intervals
  python3 ambient_temp_example.py --monitor --duration 300 --interval 10

  # Cooldown curve fitting
  python3 ambient_temp_example.py --cooldown
        """
    )

    parser.add_argument('--auto-calibrate', action='store_true',
                       help='AUTO-CALIBRATION using ACPI sensor (no thermometer needed!)')
    parser.add_argument('--auto-calibrate-weather', action='store_true',
                       help='AUTO-CALIBRATION using weather API (no thermometer needed!)')
    parser.add_argument('--test-sources', action='store_true',
                       help='Test available ambient temperature sources')
    parser.add_argument('--latitude', type=float, default=None,
                       help='Latitude for weather API (e.g., 46.8772 for North Dakota)')
    parser.add_argument('--longitude', type=float, default=None,
                       help='Longitude for weather API (e.g., -96.7898 for North Dakota)')
    parser.add_argument('--api-key', type=str, default=None,
                       help='OpenWeatherMap API key (optional, for weather mode)')
    parser.add_argument('--calibrate', action='store_true',
                       help='Interactive calibration mode (requires thermometer)')
    parser.add_argument('--calibrate-example', action='store_true',
                       help='Example calibration with synthetic data')
    parser.add_argument('--estimate', action='store_true',
                       help='Single-shot estimation mode')
    parser.add_argument('--monitor', action='store_true',
                       help='Continuous monitoring mode')
    parser.add_argument('--cooldown', action='store_true',
                       help='Cooldown curve fitting mode')
    parser.add_argument('--duration', type=int, default=300,
                       help='Monitoring duration in seconds (default: 300)')
    parser.add_argument('--interval', type=int, default=10,
                       help='Monitoring interval in seconds (default: 10)')
    parser.add_argument('--no-log', action='store_true',
                       help='Disable logging in monitor mode')

    args = parser.parse_args()

    # Execute requested mode
    if args.auto_calibrate:
        auto_calibration_mode(use_acpi=True, use_weather=False)
    elif args.auto_calibrate_weather:
        auto_calibration_mode(
            use_acpi=False,
            use_weather=True,
            latitude=args.latitude,
            longitude=args.longitude,
            api_key=args.api_key
        )
    elif args.test_sources:
        test_ambient_sources()
    elif args.calibrate:
        calibration_mode_interactive()
    elif args.calibrate_example:
        calibration_mode_example()
    elif args.estimate:
        estimation_mode_single()
    elif args.monitor:
        monitor_mode(args.duration, args.interval, not args.no_log)
    elif args.cooldown:
        cooldown_mode()
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
