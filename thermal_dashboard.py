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
from textual.widgets import Header, Footer, Static, Button, Label, DataTable, Log
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

    #logs {
        height: 1fr;
        border: solid green;
        margin: 1;
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
        self.start_time = time.time()

    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        yield Header(show_clock=True)

        with Horizontal(id="main_container"):
            with VerticalScroll(id="left_panel"):
                yield TemperatureDisplay(id="temp_display")
                yield StatusDisplay(id="status_display")

                with Vertical(id="controls"):
                    yield Label("[bold cyan]═══ MANUAL CONTROLS ═══[/]")
                    yield Button("🔥 FORCE HEATING ON", id="heat_on", classes="heat_on")
                    yield Button("❄️  FORCE HEATING OFF", id="heat_off", classes="heat_off")
                    yield Button("🔄 RESTART SERVICE", id="restart", classes="service")
                    yield Button("📊 VIEW FULL LOGS", id="view_logs", classes="service")

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

        # Check if heating is active by looking at logs
        try:
            with open('/home/mesh/thermal_manager.log', 'r') as f:
                lines = f.readlines()
                if lines:
                    last_line = lines[-1]
                    if 'HEATING' in last_line:
                        status['heating'] = 'HEATING'
                    elif 'IDLE' in last_line:
                        status['heating'] = 'IDLE'
        except:
            pass

        # Check service status
        try:
            result = subprocess.run(['systemctl', 'is-active', 'thermal-manager.service'],
                                  capture_output=True, text=True, timeout=1)
            status['service'] = result.stdout.strip()
        except:
            status['service'] = 'unknown'

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
            with open('/home/mesh/thermal_manager.log', 'r') as f:
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
            log_widget.write_line(f"[red]>>> MANUAL: Forced heating ON at {datetime.now().strftime('%H:%M:%S')}[/]")

        elif button_id == "heat_off":
            self.force_heating_off()
            log_widget.write_line(f"[blue]>>> MANUAL: Forced heating OFF at {datetime.now().strftime('%H:%M:%S')}[/]")

        elif button_id == "restart":
            self.restart_service()
            log_widget.write_line(f"[green]>>> SERVICE: Restarting thermal manager...[/]")

        elif button_id == "view_logs":
            self.action_view_full_logs()

    def force_heating_on(self) -> None:
        """Force heating on (manual override)"""
        # Create override file to signal thermal manager
        with open(self.override_file, 'w') as f:
            f.write("HEATING_ON")

        # Could also directly modify the thermal manager or send signal
        # For now, we'll just create a marker file

    def force_heating_off(self) -> None:
        """Force heating off (manual override)"""
        with open(self.override_file, 'w') as f:
            f.write("HEATING_OFF")

    def restart_service(self) -> None:
        """Restart the thermal manager service"""
        try:
            subprocess.run(['sudo', 'systemctl', 'restart', 'thermal-manager.service'],
                         check=True, timeout=5)
        except:
            pass

    def action_view_full_logs(self) -> None:
        """View full logs in less"""
        self.exit()
        os.system('less +G /home/mesh/thermal_manager.log')

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
