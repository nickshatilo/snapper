# Snapper

Open-source screenshot tool for macOS. Aims for local feature parity with CleanShot X — no cloud, no subscriptions.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)
[![CI](https://github.com/nickshatilo/snapper/actions/workflows/ci.yml/badge.svg)](https://github.com/nickshatilo/snapper/actions/workflows/ci.yml)

## Features

**Capture Modes**
- **Fullscreen** — single display or all monitors
- **Area Selection** — crosshair with magnifier loupe, pixel coordinates, dimension overlay
- **Window Capture** — hover-to-highlight, configurable shadow and background
- **All-in-One HUD** — pick any mode from a single overlay (like ⌘⇧5)
- **Scrolling Capture** — auto-scroll and stitch long content
- **OCR** — select area, extract text on-device via Apple Vision (copied to clipboard)
- **Self-Timer** — 3/5/10 second countdown on any capture mode

**Quick Access Overlay**
- Floating thumbnail after every capture, persistent until dismissed
- Stack multiple captures, drag-and-drop into any app
- One-click copy, save, annotate, pin, or delete

**Annotation Editor**
- Arrow, rectangle, ellipse, line, pencil, highlighter, text, blur, pixelate, spotlight, counter, crop
- Background/mockup tool with gradient and solid color templates
- Non-destructive editing with `.snapper` project format
- Undo/redo, keyboard shortcuts for every tool

**Floating Screenshots**
- Pin captures as always-on-top windows
- Resize, adjust opacity, lock (click-through mode)
- Persists across app restarts

**History**
- Local SQLite database via SwiftData
- Browse, search by OCR text, filter by capture type
- Configurable retention and storage location

**Other**
- Menu bar agent app (no dock icon)
- Global hotkeys via CGEvent taps (replaces ⌘⇧3/4/5)
- Fully customizable shortcuts with conflict detection
- Auto-updates via Sparkle
- Launch at login

## Install

### Download

Grab the latest `.dmg` from [Releases](https://github.com/nickshatilo/snapper/releases).

### Build from Source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/nickshatilo/snapper.git
cd snapper
xcodegen generate
open Snapper.xcodeproj
```

Build and run the `Snapper` scheme.

### Permissions

Snapper needs two permissions on first launch:

1. **Screen Recording** — for capturing your screen
2. **Accessibility** — for global hotkey registration

## Default Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧3` | Capture Fullscreen |
| `⌘⇧4` | Capture Area |
| `⌘⇧4` → hover | Capture Window |
| `⌘⇧5` | All-in-One Mode |

All shortcuts are customizable in Settings → Shortcuts.

## Contributing

1. Fork the repo
2. Create a feature branch
3. Make your changes
4. Run tests: `xcodebuild test -scheme Snapper -destination 'platform=macOS'`
5. Open a PR

## License

MIT
