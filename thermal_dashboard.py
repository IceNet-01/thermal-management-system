#!/usr/bin/env python3
"""
Thermal Management Dashboard - Terminal GUI
Similar to Nomadnet interface style
"""

import os
import time
import subprocess
from datetime import datetime
from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical, VerticalScroll
from textual.widgets import Header, Footer, Static, Button, Label, DataTable, Log, Input
from textual.reactive import reactive
from textual import work
from textual.timer import Timer


class TemperatureDisplay(Static):
    """Display current temperatures"""
    acpi_temp = reactive(0.0)
    cpu_temp = reactive(0.0)

    def render(self) -> str:
        acpi_f = (self.acpi_temp * 9/5) + 32
        cpu_f = (self.cpu_temp * 9/5) + 32

        # Color coding based on temperature
        acpi_color = "green" if self.acpi_temp > 0 else "red"

        return f"""
[bold cyan]═══════════════════════════════════════════════════[/]
[bold white]           TEMPERATURE MONITORING[/]
[bold cyan]═══════════════════════════════════════════════════[/]

  [bold]ACPI (Case Ambient):[/]
    [{acpi_color}]▓▓▓▓▓ {self.acpi_temp:5.1f}°C ({acpi_f:5.1f}°F) ▓▓▓▓▓[/]

  [bold]CPU Package:[/]
    [yellow]▓▓▓▓▓ {self.cpu_temp:5.1f}°C ({cpu_f:5.1f}°F) ▓▓▓▓▓[/]

[bold cyan]═══════════════════════════════════════════════════[/]
"""


class StatusDisplay(Static):
    """Display system status"""
    heating_status = reactive("UNKNOWN")
    service_status = reactive("UNKNOWN")
    uptime = reactive("--:--:--")
    manual_override = reactive(False)

    def render(self) -> str:
        # Status colors
        heat_color = "red" if self.heating_status == "HEATING" else "green"
        service_color = "green" if "active" in self.service_status.lower() else "red"

        override_text = "[yellow]MANUAL OVERRIDE ACTIVE[/]" if self.manual_override else ""

        return f"""
[bold cyan]═══════════════════════════════════════════════════[/]
[bold white]              SYSTEM STATUS[/]
[bold cyan]═══════════════════════════════════════════════════[/]

  [bold]Heating:[/] [{heat_color}]● {self.heating_status}[/]
  [bold]Service:[/] [{service_color}]● {self.service_status}[/]
  [bold]Uptime:[/]  [white]{self.uptime}[/]

  {override_text}

[bold cyan]═══════════════════════════════════════════════════[/]
"""


class ThermalDashboard(App):
    """Thermal Management Dashboard TUI Application"""

    CSS = """
    Screen {
        background: $surface;
    }

    #main_container {
        width: 100%;
        height: 100%;
        background: $surface;
    }

    #left_panel {
        width: 55;
        height: 100%;
        border: solid cyan;
    }

    #right_panel {
        width: 1fr;
        height: 100%;
        border: solid cyan;
    }

    #controls {
        height: auto;
        padding: 1;
        border: solid yellow;
        margin: 1;
    }

    #config {
        height: auto;
        padding: 1;
        border: solid cyan;
        margin: 1;
    }

    #logs {
        height: 1fr;
        border: solid green;
        margin: 1;
    }

    Input {
        margin: 0 1;
        width: 100%;
    }

    Button {
        margin: 1;
        width: 100%;
    }

    Button.heat_on {
        background: red;
        color: white;
    }

    Button.heat_off {
        background: blue;
        color: white;
    }

    Button.service {
        background: green;
        color: white;
    }

    Log {
        background: $surface;
        color: $text;
    }
    """

    BINDINGS = [
        ("q", "quit", "Quit"),
        ("r", "refresh", "Refresh"),
        ("h", "toggle_heating", "Toggle Heat"),
        ("s", "restart_service", "Restart Service"),
        ("up", "scroll_up", "Scroll Up"),
        ("down", "scroll_down", "Scroll Down"),
    ]

    def __init__(self):
        super().__init__()
        self.override_file = "/tmp/thermal_override"
        self.config_file = "/tmp/thermal_config"
        self.start_time = time.time()
        # Use environment variable or fallback to default location
        self.log_file = os.environ.get("LOG_FILE", "/var/log/thermal-manager/thermal_manager.log")

        # Load current config or use defaults
        self.temp_min = 0
        self.temp_target = 5
        self.load_config()

    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        yield Header(show_clock=True)

        with Horizontal(id="main_container"):
            with VerticalScroll(id="left_panel"):
                yield TemperatureDisplay(id="temp_display")
                yield StatusDisplay(id="status_display")

                with Vertical(id="controls"):
                    yield Label("[bold cyan]═══ MANUAL CONTROLS ═══[/]")
                    yield Button("🔥 MANUAL ON (Override)", id="heat_on", classes="heat_on")
                    yield Button("❄️  MANUAL OFF (Auto Mode)", id="heat_off", classes="heat_off")
                    yield Button("🔄 RESTART SERVICE", id="restart", classes="service")
                    yield Button("📊 VIEW FULL LOGS", id="view_logs", classes="service")

                with Vertical(id="config"):
                    yield Label("[bold cyan]═══ TEMPERATURE CONFIG ═══[/]")
                    yield Label("Start Heating Below (°C):")
                    yield Input(placeholder="0", id="temp_min", value=str(self.temp_min))
                    yield Label("Stop Heating Above (°C):")
                    yield Input(placeholder="5", id="temp_target", value=str(self.temp_target))
                    yield Button("💾 SAVE CONFIG", id="save_config", classes="service")

            with Vertical(id="right_panel"):
                yield Label("[bold cyan]═══════════ RECENT ACTIVITY ═══════════[/]", id="log_header")
                yield Log(id="logs", max_lines=100)

        yield Footer()

    def on_mount(self) -> None:
        """Set up the application on mount."""
        self.update_data()
        self.set_interval(2.0, self.update_data)

        # Load initial logs
        self.load_logs()

    @work(exclusive=True)
    async def update_data(self) -> None:
        """Update all dashboard data"""
        # Get temperatures
        temps = self.get_temperatures()
        temp_display = self.query_one("#temp_display", TemperatureDisplay)
        temp_display.acpi_temp = temps['acpi']
        temp_display.cpu_temp = temps['cpu']

        # Get status
        status = self.get_status()
        status_display = self.query_one("#status_display", StatusDisplay)
        status_display.heating_status = status['heating']
        status_display.service_status = status['service']
        status_display.uptime = status['uptime']
        status_display.manual_override = os.path.exists(self.override_file)

    def get_temperatures(self) -> dict:
        """Read current temperatures"""
        temps = {'acpi': 0.0, 'cpu': 0.0}

        try:
            with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                temps['acpi'] = int(f.read().strip()) / 1000.0
        except:
            pass

        try:
            with open('/sys/class/thermal/thermal_zone1/temp', 'r') as f:
                temps['cpu'] = int(f.read().strip()) / 1000.0
        except:
            pass

        return temps

    def get_status(self) -> dict:
        """Get system status"""
        status = {
            'heating': 'UNKNOWN',
            'service': 'UNKNOWN',
            'uptime': '--:--:--'
        }

        # Check if heating is active by looking at logs (use sudo to read)
        try:
            result = subprocess.run(['sudo', 'tail', '-10', self.log_file],
                                  capture_output=True, text=True, timeout=2)
            if result.returncode == 0 and result.stdout:
                lines = result.stdout.split('\n')
                # Check last few lines for most recent status
                for line in reversed(lines):
                    if line.strip():
                        if 'HEATING ON:' in line or 'HEATING:' in line:
                            status['heating'] = 'HEATING'
                            break
                        elif 'HEATING OFF:' in line or 'IDLE:' in line or 'IDLE (' in line:
                            status['heating'] = 'IDLE'
                            break
        except Exception as e:
            # If log file doesn't exist or can't be read, status stays UNKNOWN
            pass

        # Check service status (use sudo since we're not root)
        try:
            result = subprocess.run(['sudo', 'systemctl', 'is-active', 'thermal-manager.service'],
                                  capture_output=True, text=True, timeout=2)
            svc_status = result.stdout.strip()
            # Make it more readable
            if svc_status == 'active':
                status['service'] = 'ACTIVE'
            elif svc_status == 'inactive':
                status['service'] = 'INACTIVE'
            elif svc_status == 'failed':
                status['service'] = 'FAILED'
            else:
                status['service'] = svc_status.upper()
        except Exception as e:
            status['service'] = 'UNKNOWN'

        # Calculate uptime
        uptime_seconds = int(time.time() - self.start_time)
        hours = uptime_seconds // 3600
        minutes = (uptime_seconds % 3600) // 60
        seconds = uptime_seconds % 60
        status['uptime'] = f"{hours:02d}:{minutes:02d}:{seconds:02d}"

        return status

    def load_logs(self) -> None:
        """Load recent logs into the log viewer"""
        log_widget = self.query_one("#logs", Log)

        try:
            # Try to read log file with sudo if needed
            result = subprocess.run(['sudo', 'tail', '-50', self.log_file],
                                  capture_output=True, text=True, timeout=2)
            if result.returncode == 0 and result.stdout:
                for line in result.stdout.split('\n'):
                    if line.strip():
                        log_widget.write_line(line.strip())
            else:
                log_widget.write_line("[yellow]No logs available yet[/]")
        except Exception as e:
            log_widget.write_line(f"[yellow]Cannot read logs: {str(e)}[/]")
            with open(self.log_file, 'r') as f:
                lines = f.readlines()
                for line in lines[-50:]:  # Last 50 lines
                    log_widget.write_line(line.strip())
        except:
            log_widget.write_line("[yellow]No logs available yet[/]")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses"""
        button_id = event.button.id
        log_widget = self.query_one("#logs", Log)

        if button_id == "heat_on":
            self.force_heating_on()
            log_widget.write_line(f"[red]>>> MANUAL ON: Heating forced ON (auto disabled) at {datetime.now().strftime('%H:%M:%S')}[/]")

        elif button_id == "heat_off":
            # Manual OFF returns to auto mode (clears override)
            self.clear_override()
            log_widget.write_line(f"[blue]>>> MANUAL OFF: Returning to AUTO mode at {datetime.now().strftime('%H:%M:%S')}[/]")

        elif button_id == "restart":
            self.restart_service()
            log_widget.write_line(f"[green]>>> SERVICE: Restarting thermal manager...[/]")

        elif button_id == "view_logs":
            self.action_view_full_logs()

        elif button_id == "save_config":
            if self.save_config_from_inputs():
                log_widget.write_line(f"[green]>>> CONFIG: Temperature thresholds saved at {datetime.now().strftime('%H:%M:%S')}[/]")
                log_widget.write_line(f"[green]    Start heating below: {self.temp_min}°C, Stop above: {self.temp_target}°C[/]")
            else:
                log_widget.write_line(f"[red]>>> CONFIG: Failed to save - check input values[/]")

    def force_heating_on(self) -> None:
        """Force heating on (manual override)"""
        try:
            with open(self.override_file, 'w') as f:
                f.write("HEATING_ON")
            # Make sure it's world-readable so the service can read it
            os.chmod(self.override_file, 0o644)
        except Exception as e:
            print(f"Error creating override file: {e}")

    def clear_override(self) -> None:
        """Clear manual override - return to automatic mode"""
        try:
            if os.path.exists(self.override_file):
                os.remove(self.override_file)
        except:
            pass

    def load_config(self) -> None:
        """Load temperature configuration from file"""
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    lines = f.readlines()
                    for line in lines:
                        line = line.strip()
                        if line.startswith("TEMP_MIN="):
                            self.temp_min = int(line.split("=")[1])
                        elif line.startswith("TEMP_TARGET="):
                            self.temp_target = int(line.split("=")[1])
        except Exception as e:
            print(f"Error loading config: {e}")
            # Use defaults
            self.temp_min = 0
            self.temp_target = 5

    def save_config_from_inputs(self) -> bool:
        """Save temperature configuration from input widgets"""
        try:
            # Get input values
            temp_min_input = self.query_one("#temp_min", Input)
            temp_target_input = self.query_one("#temp_target", Input)

            # Validate inputs
            temp_min = int(temp_min_input.value)
            temp_target = int(temp_target_input.value)

            if temp_target <= temp_min:
                return False  # Invalid: target must be higher than min

            # Save to instance
            self.temp_min = temp_min
            self.temp_target = temp_target

            # Write config file
            with open(self.config_file, 'w') as f:
                f.write(f"TEMP_MIN={temp_min}\n")
                f.write(f"TEMP_TARGET={temp_target}\n")

            # Make it world-readable so the service can read it
            os.chmod(self.config_file, 0o644)
            return True
        except Exception as e:
            print(f"Error saving config: {e}")
            return False

    def restart_service(self) -> None:
        """Restart the thermal manager service"""
        try:
            # Use pkexec instead of sudo for GUI apps (no terminal required)
            # Falls back to sudo if pkexec not available
            if os.path.exists('/usr/bin/pkexec'):
                subprocess.run(['pkexec', 'systemctl', 'restart', 'thermal-manager.service'],
                             check=True, timeout=10)
            else:
                subprocess.run(['sudo', 'systemctl', 'restart', 'thermal-manager.service'],
                             check=True, timeout=5)
        except Exception as e:
            pass

    def action_view_full_logs(self) -> None:
        """View full logs in less"""
        self.exit()
        os.system(f'sudo less +G {self.log_file}')
        os.system(f'less +G {self.log_file}')

    def action_refresh(self) -> None:
        """Manual refresh"""
        self.update_data()
        self.load_logs()

    def action_toggle_heating(self) -> None:
        """Toggle heating via keyboard shortcut"""
        status = self.get_status()
        if status['heating'] == 'HEATING':
            self.force_heating_off()
        else:
            self.force_heating_on()

    def action_scroll_up(self) -> None:
        """Scroll the left panel up"""
        left_panel = self.query_one("#left_panel")
        left_panel.scroll_up()

    def action_scroll_down(self) -> None:
        """Scroll the left panel down"""
        left_panel = self.query_one("#left_panel")
        left_panel.scroll_down()


if __name__ == "__main__":
    app = ThermalDashboard()
    app.run()
