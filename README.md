# Snapper

Open-source screenshot tool for macOS. Aims for local feature parity with CleanShot X — no cloud, no subscriptions.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)
[![CI](https://github.com/nickshatilo/snapper/actions/workflows/ci.yml/badge.svg)](https://github.com/nickshatilo/snapper/actions/workflows/ci.yml)

## Features

**Capture Modes**
- **Fullscreen** — every connected display, composed into one image
- **Area Selection** — crosshair with live pixel dimensions, optional magnifier loupe and frozen screen
- **Window Capture** — hover-to-highlight, optional window shadow
- **All-in-One HUD** — pick any mode from a single overlay (like ⌘⇧5)
- **Scrolling Capture** — auto-scroll and stitch long content
- **OCR** — select area, extract text on-device via Apple Vision (copied to clipboard)
- **Self-Timer** — 3/5/10 second countdown on any capture mode from the HUD, Esc to cancel

**Quick Access Overlay**
- Floating thumbnail after every capture, persistent until dismissed
- Stack multiple captures, drag-and-drop into any app
- One-click copy, save or reveal in Finder, annotate, pin, or move to Trash

**Annotation Editor**
- Arrow, rectangle, ellipse, line, pencil, highlighter, text, blur, pixelate, spotlight, counter, crop
- OCR tool to select and copy text from any screenshot
- Undo/redo, keyboard shortcuts for every tool

**Floating Screenshots**
- Pin captures as always-on-top windows
- Resize, adjust opacity, lock in place
- Persists across app restarts

**History**
- Local SQLite database via SwiftData
- Browse, search by OCR text, filter by capture type
- Configurable retention

**Other**
- Menu bar agent app (no dock icon)
- Global hotkeys via CGEvent taps (replaces ⌘⇧3/4/5)
- Fully customizable shortcuts with conflict detection
- Auto-updates via Sparkle
- Launch at login
- Show or hide desktop icons from the menu bar

Updates are delivered in-app through Sparkle. Snapper verifies both the signed
appcast and update archive before installing, while macOS independently verifies
the Developer ID signature and notarization.

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

The project uses manual Developer ID signing with the maintainer's team. To build
with your own Apple certificate, change `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY`
in `project.yml` before running `xcodegen generate`.

### Permissions

Snapper needs two permissions on first launch:

1. **Screen Recording** — for capturing your screen
2. **Accessibility** — for global hotkey registration

## Default Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧3` | Capture Fullscreen |
| `⌘⇧4` | Capture Area |
| `⌘⇧5` | All-in-One HUD |

Window, scrolling, OCR and timer capture and the desktop-icons toggle have no
shortcut by default. Assign or change any of them in Settings → Shortcuts.

## Contributing

1. Fork the repo
2. Create a feature branch
3. Make your changes
4. Run tests: `xcodebuild test -scheme Snapper -destination 'platform=macOS'`
5. Open a PR

## License

[MIT](LICENSE)
