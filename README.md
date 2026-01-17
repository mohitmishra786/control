<p align="center">
  <img src="https://img.shields.io/badge/macOS-12.0+-blue?style=flat-square" alt="macOS 12.0+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange?style=flat-square" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
  <a href="https://x.com/chessMan786"><img src="https://img.shields.io/badge/follow-chessMan786-1DA1F2?style=flat-square&logo=twitter" alt="Twitter"></a>
</p>

<h1 align="center">Control</h1>

<p align="center">
  <em>Linux level power for your Mac. One binary to rule them all.</em>
</p>

## The Problem

macOS power users face a frustrating reality. Fundamental system controls are either missing or locked behind third party paywalls.

| Pain Point | Current Workaround | Cost |
|------------|-------------------|------|
| Window tiling and snapping | Magnet, Rectangle, BetterSnapTool | $0 to $10 |
| Mouse acceleration disable | LinearMouse, USB Overdrive | $0 to $20 |
| Permission reauthorization | Amnesia | Pay what you want |
| Per device scroll direction | Multiple apps required | Various |

> "It is unbelievable how bad window management is at macOS. Especially if you use multiple desktops, it's impossible to not kill your workflow."
> — Hacker News, 2024

Control consolidates these fragmented solutions into a single, free, open source tool.

## Features

### Window Management

**Corner Grab Fix** fixes macOS Tahoe's oversized corner radii (20px) that make window edge grabs imprecise. Uses 1px precision with invisible 5px hit boxes.

**Tiling Engine** provides keyboard driven layouts including halves, thirds, quarters, and custom zones.

**Snap Handler** enables drag to edge snapping with visual feedback overlay.

**Display Persistence** remembers window positions when displays reconnect. No more window jumble after waking from sleep.

### Input Control

**Raw 1:1 Input** disables mouse acceleration completely for precision workflows.

**Per Device Scroll Direction** gives you natural scrolling for trackpad and traditional for mouse. Finally independent.

**Custom Acceleration Curves** support linear, exponential, or custom Bezier interpolation using a Newton Raphson solver.

**Gesture Mapping** translates multi finger trackpad gestures to custom actions, integrating with Shortcuts.app.

### Permission Management (SIP Safe)

> Control never writes directly to TCC.db. All automation uses Apple approved mechanisms.

**Permission Scanner** performs read only TCC database inspection with categorized display.

**UI Automation** clicks Allow buttons automatically using the Accessibility API.

**Amnesia Method** extends screen recording permissions via plist modification.

**Quarantine Handler** removes quarantine attributes with Touch ID confirmation.

**Trust Lists** fast track trusted apps with pattern matching (for example `com.jetbrains.*`).

### UI Consistency

**UI Harmonizer** standardizes traffic light button sizes and positions across apps.

**Icon Normalizer** normalizes Dock and menu bar icons with shape masks including rounded square, circle, and squircle.

**Menu Bar Manager** hides, shows, and reorders menu bar items via SIP safe defaults commands.

**Theme Engine** applies system wide color schemes and dark mode enhancements.

### Background Daemon

**Pulse Monitor** watches memory usage and restarts automatically if the daemon exceeds 150MB. This prevents runaway memory leaks from affecting system performance.

**Hot Reload** applies configuration changes without restarting the daemon. Edit the config file and see changes immediately.

## Installation

### Homebrew (Recommended)

```bash
brew install mohitmishra786/tap/control
```

### From Source

```bash
git clone https://github.com/mohitmishra786/control.git
cd control
swift build -c release
# Binary located at .build/release/control
```

### Using the Installer

```bash
./install.sh --prefix /usr/local
```

## Quick Start

```bash
# Check system status
control status

# Enable corner grab precision fix
control window corner-fix --enable

# Disable mouse acceleration (1:1 raw input)
control input acceleration --disable

# Set per device scroll direction
control input scroll --device mouse --traditional
control input scroll --device trackpad --natural

# View permission status
control permission status

# Install as background daemon
control daemon install
control daemon start
```

## Configuration

Control uses TOML configuration stored at `~/.config/control/control.toml`:

```toml
[window]
corner_fix_enabled = true
corner_precision_px = 1
snap_enabled = true
snap_threshold_px = 20
tiling_enabled = true
default_layout = "developer"

[window.zones]
left_half = { x = 0.0, y = 0.0, width = 0.5, height = 1.0 }
right_half = { x = 0.5, y = 0.0, width = 0.5, height = 1.0 }

[input]
mouse_acceleration_enabled = false
trackpad_natural_scroll = true
mouse_natural_scroll = false

[permission]
developer_mode = true
ui_automation_enabled = true

[daemon]
enabled = true
pulse_max_memory_mb = 150
pulse_check_interval_seconds = 30

[core]
log_level = "info"
```

Presets are available in `config/presets/` for developer, designer, and minimal configurations.

## Architecture

Control follows a layered architecture with clear separation of concerns. See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed diagrams.

| Layer | Purpose |
|-------|---------|
| CLI | Argument parsing, user interaction |
| Modules | Domain logic for window, input, permission, UI |
| Shared | Config, logging, security, system utilities |

## Modules

| Module | Command | Purpose |
|--------|---------|---------|
| Window | `control window` | Tiling, snapping, corner fixes |
| Input | `control input` | Acceleration, scroll, gestures |
| Permission | `control permission` | SIP safe permission automation |
| Consistency | `control consistency` | UI harmonization |
| Daemon | `control daemon` | Background service |
| Config | `control config` | Configuration management |
| Status | `control status` | System overview |

## Requirements

macOS 12.0 or later (Monterey and beyond)

Swift 6.0 or later (for building from source)

Accessibility permission (for window and input control)

## Philosophy

| Principle | What It Means |
|-----------|---------------|
| Safety First | Never compromise system stability or user data |
| Zero Trust | Validate everything, assume nothing |
| Linux Parity | Provide power user controls that Linux offers natively |
| Performance | Native Swift speed, sub 100MB memory footprint |
| Transparency | Open source, no telemetry without consent |

## Roadmap

### Phase 1: Foundation ✓
- [x] Core CLI structure
- [x] Window Manager with corner grab fix
- [x] Tiling Engine with custom zones
- [x] Snap Handler with visual feedback

### Phase 2: Production Hardening ✓
- [x] Input Controller with acceleration curves
- [x] Gesture Mapper for trackpad actions
- [x] Permission Manager with TCC scanner
- [x] UI Harmonizer and Theme Engine
- [x] Configuration hot reload
- [x] Daemon with Pulse Monitor
- [x] Display persistence for multi monitor setups
- [x] Security audit logging

### Phase 3: Polish (In Progress)
- [ ] GUI configuration editor
- [ ] Community presets
- [ ] Homebrew formula
- [ ] Notarized release builds

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

```bash
# Clone and build
git clone https://github.com/mohitmishra786/control.git
cd control
swift build

# Run tests
swift test

# Run the CLI
swift run control --help
```

## Inspiration

Control consolidates ideas from tools that macOS power users have relied on for years:

[Mole](https://github.com/tw93/Mole) demonstrated viral success by consolidating macOS system utilities

[Rectangle](https://github.com/rxhanson/Rectangle) proved the demand for open source window management

[LinearMouse](https://github.com/linearmouse/linearmouse) showed that mouse acceleration control matters

Desktop environments like KDE Plasma, GNOME, and i3 where power user control is built in rather than bolted on

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

<p align="center">
  <sub>Built with care for macOS power users who miss their Linux workflows.</sub>
</p>
