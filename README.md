# Control

> *"Linux-like power for macOS — One binary to rule your Mac."*

**Control** is a single, efficient, open-source binary that consolidates fragmented macOS interaction and workflow management tools. It addresses critical pain points in macOS Sequoia/Tahoe that frustrate power users and drive them toward Linux alternatives.

---

## The Problem

macOS power users face a frustrating reality: *fundamental system controls are either missing or locked behind third-party paywalls*.

| Pain Point | Current Workaround | Cost |
|------------|-------------------|------|
| Window tiling & snapping | Magnet, Rectangle, BetterSnapTool | $0-$10 |
| Mouse acceleration disable | LinearMouse, USB Overdrive | $0-$20 |
| Permission reauthorization | Amnesia | Pay-what-you-want |
| Per-device scroll direction | Multiple apps required | Various |

> *"It is unbelievable how bad window management is at macOS. Especially if you use multiple desktops, it's impossible to not kill your workflow."*
> — Hacker News, 2024

Control aims to consolidate these fragmented solutions into a **single, free, open-source tool** — following the success pattern of [Mole](https://github.com/tw93/Mole).

---

## Features

### Window Management

- **Corner Grab Fix** — Fixes macOS Tahoe's oversized corner radii (20px) that make window edge grabs imprecise. Uses 1px precision with invisible 5px hit-boxes.
- **Tiling Engine** — Keyboard-driven layouts: *halves, thirds, quarters*, and custom zones.
- **Snap Handler** — Drag-to-edge snapping with visual feedback overlay.
- **Traffic Light Normalizer** — Standardizes inconsistent traffic light button positions across apps.

### Input Control

- **Raw 1:1 Input** — Disable mouse acceleration completely for precision workflows.
- **Per-Device Scroll Direction** — Natural scrolling for trackpad, *traditional for mouse* — finally independent.
- **Custom Acceleration Curves** — Linear, exponential, or custom Bezier interpolation.
- **Gesture Mapping** — Map trackpad gestures to custom actions, integrate with Shortcuts.app.

### Permission Management *(SIP-Safe)*

> **Important:** Control *never writes directly to TCC.db*. All automation uses Apple-approved mechanisms.

- **Permission Scanner** — Read-only TCC database inspection with categorized display.
- **UI Automation** — Automatically click "Allow" buttons using Accessibility API.
- **Amnesia Method** — Extend screen recording permissions via plist modification.
- **Quarantine Handler** — Remove quarantine attributes with Touch ID confirmation.
- **Trust Lists** — Fast-track trusted apps with pattern matching (e.g., `com.jetbrains.*`).

### UI Consistency

- **UI Harmonizer** — Standardize button sizes and positions across apps.
- **Icon Normalizer** — Normalize Dock and menu bar icons with shape masks.
- **Menu Bar Manager** — Hide, show, and reorder menu bar items.
- **Theme Engine** — Apply system-wide color schemes and dark mode enhancements.

---

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

---

## Quick Start

```bash
# Check system status
control status

# Enable corner grab precision fix
control window corner-fix --enable

# Disable mouse acceleration (1:1 raw input)
control input acceleration --disable

# Set per-device scroll direction
control input scroll --device mouse --traditional
control input scroll --device trackpad --natural

# View permission status
control permission status

# Install as background daemon
control daemon install
control daemon start
```

---

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

[core]
log_level = "info"
daemon_enabled = true
```

---

## Why Control?

### Philosophy

| Principle | Description |
|-----------|-------------|
| **Safety First** | Never compromise system stability or user data |
| **Zero Trust** | Validate everything, assume nothing |
| **Linux Parity** | Provide power-user controls that Linux offers natively |
| **Performance** | Native Swift speed, sub-100MB memory footprint |
| **Transparency** | Open source, no telemetry without consent |

### Technical Excellence

- **Native Swift** — No Electron bloat, direct macOS framework integration
- **SIP-Compatible** — Works with System Integrity Protection enabled
- **Sub-5ms Latency** — Event interception that doesn't lag the system
- **Modular Architecture** — Enable only what you need

---

## Requirements

- **macOS 12.0+** (Monterey and later)
- **Swift 6.0+** (for building from source)
- **Accessibility Permission** (for window and input control)

---

## Modules

| Module | Command | Purpose |
|--------|---------|---------|
| Window | `control window` | Tiling, snapping, corner fixes |
| Input | `control input` | Acceleration, scroll, gestures |
| Permission | `control permission` | SIP-safe permission automation |
| Consistency | `control consistency` | UI harmonization |
| Daemon | `control daemon` | Background service |
| Config | `control config` | Configuration management |
| Status | `control status` | System overview |

---

## Roadmap

### Phase 1: Foundation (Current)
- [x] Core CLI structure
- [x] Window Manager with corner grab fix
- [ ] Input Controller with acceleration controls
- [ ] Permission Manager (read-only)

### Phase 2: Enhancement
- [ ] Tiling Engine with custom zones
- [ ] Per-device input settings
- [ ] UI Automation for permissions
- [ ] Daemon with background monitoring

### Phase 3: Polish
- [ ] GUI configuration editor
- [ ] Theme Engine
- [ ] Community presets
- [ ] Homebrew formula

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

### Development

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

---

## Inspiration

Control draws inspiration from:

- **[Mole](https://github.com/tw93/Mole)** — Demonstrated viral success by consolidating macOS system utilities
- **[Rectangle](https://github.com/rxhanson/Rectangle)** — Popular open-source window management (24k+ GitHub stars)
- **[LinearMouse](https://github.com/linearmouse/linearmouse)** — Proven demand for mouse acceleration control
- **Linux Desktop Environments** — KDE Plasma, GNOME, i3 — where power-user control is built-in

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <sub>Built with care for macOS power users who miss their Linux workflows.</sub>
</p>
