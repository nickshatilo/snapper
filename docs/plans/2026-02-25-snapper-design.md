# Snapper — Product Design Document

> Open source macOS screenshot tool with full CleanShot X local feature parity.
> No cloud features. Screenshots only (no video/GIF recording).

## Tech Stack

- **Language**: Swift
- **UI Framework**: SwiftUI (with AppKit bridging for window management)
- **Minimum macOS**: 13 (Ventura)
- **License**: MIT
- **Distribution**: GitHub Releases + Homebrew cask, Sparkle auto-updater

---

## 1. App Shell & Lifecycle

### App Type
- **LSUIElement agent app** — no dock icon, no main window on launch
- Optional **menu bar icon** (NSStatusItem), togglable in preferences
- When menu bar icon is hidden: re-launching the .app opens Settings (single-instance check via `NSRunningApplication`)

### Global Hotkeys
Registered via `CGEvent` taps (requires Accessibility permission). Replaces macOS built-in screenshot shortcuts:

| Shortcut (default) | Action |
|---|---|
| `Cmd+Shift+3` | Capture Fullscreen |
| `Cmd+Shift+4` | Capture Area (crosshair selector) |
| `Cmd+Shift+4` → hover window | Capture Window |
| `Cmd+Shift+5` | All-in-One mode |
| Configurable | Scrolling Capture |
| Configurable | OCR (Text Recognition) |
| Configurable | Self-Timer Capture |
| Configurable | Toggle Desktop Icons |

All shortcuts are fully customizable in preferences with conflict detection.

### Startup
- **Launch at login** via `SMAppService` (macOS 13+)
- First-run onboarding: request Accessibility + Screen Recording permissions, offer to replace system screenshot shortcuts

---

## 2. Capture Engine

### Implementation
- **ScreenCaptureKit** (`SCScreenshotManager` / `SCShareableContent`) for all capture operations
- Privacy-aware: leverages macOS screen recording permission prompt

### Capture Modes

#### Fullscreen
- Captures entire focused display
- Multi-monitor: option to capture all displays as separate images or stitched

#### Area Selection
- Crosshair cursor with pixel coordinates display
- Magnifier loupe at cursor for pixel-precise selection
- Dimension overlay showing WxH of selection
- Pixel-snapping to edges

#### Window Capture
- Highlight window under cursor on hover
- Click to capture
- Options: include/exclude shadow, background style (desktop wallpaper, solid color, custom image, transparent)

#### All-in-One Mode
- HUD overlay (similar to macOS Cmd+Shift+5 panel)
- Choose any capture mode from a single interface
- Set timer, toggle options
- Remembers previous selection area

#### Scrolling Capture
- Select area, then auto-scroll + stitch
- Uses `CGWindowListCreateImage` at intervals with image stitching algorithm
- Works in most scrollable content (browsers, documents, code editors)

#### OCR (Text Recognition)
- Area selection, then **Apple Vision framework** `VNRecognizeTextRequest`
- On-device processing (private, no network)
- Extracted text copied to clipboard
- Optional: show extracted text in a popup for review/editing before copying

#### Self-Timer
- Available as a toggle in any capture mode
- 3 / 5 / 10 second countdown overlay
- Visual countdown indicator on screen

### Capture Options
- **Freeze screen**: overlay a full-screen snapshot so user selects on a frozen frame
- **Hide desktop icons**: temporarily set Finder's `CreateDesktop` preference to false, restore after capture
- **Capture sound**: optional shutter sound (system or custom), off by default
- **Clipboard**: all captures automatically copied to clipboard (configurable)
- **File output**: configurable save location, filename pattern, format (PNG/JPEG/TIFF)

---

## 3. Quick Access Overlay

The floating thumbnail that appears after every capture. **Persistent until manually dismissed.**

### Behavior
- Appears immediately after capture as a thumbnail in a configurable screen corner
- **Never auto-closes** — remains until the user explicitly dismisses it
- Multiple captures **stack vertically**, newest on top
- Scrollable if many captures are stacked
- Each thumbnail shows: preview image, file size, dimensions

### Interactions
- **Hover**: reveals action buttons — Copy, Save, Annotate, Pin (float), Delete
- **Drag-and-drop**: drag thumbnail directly into any app (Finder, Slack, Mail, etc.) via `NSPasteboardItem`
- **Swipe right**: dismiss individual capture
- **Click**: opens annotation editor

### Implementation
- `NSPanel` with `.floating` window level
- `NSVisualEffectView` for vibrancy/blur background
- Non-activating: does not steal focus from the current application
- Configurable position and thumbnail size in preferences

---

## 4. Floating (Pinned) Screenshots

Captures promoted from the Quick Access Overlay to persistent floating windows.

### Behavior
- **Stays above all other windows** (`.floating` window level on `NSPanel`)
- Multiple pinned screenshots can coexist on screen
- **Persists across app restarts** — positions, sizes, and opacity saved to UserDefaults

### Interactions
- **Resize**: drag corners/edges
- **Move**: drag title area or anywhere on the image
- **Arrow key nudging**: pixel-precise positioning
- **Scroll gesture**: adjust opacity
- **Lock mode**: `ignoresMouseEvents = true` — clicks pass through to apps underneath
- **Context menu**: Close, Copy, Save, Annotate, Opacity slider, Lock/Unlock, Always on Top toggle

### Appearance
- Configurable: rounded corners, shadow, border
- Configurable default opacity

---

## 5. Annotation Editor

Full-featured image editor opened from the Quick Access Overlay, pinned screenshot context menu, history browser, or by double-clicking a saved capture.

### Canvas
- SwiftUI window with **Core Graphics-backed rendering canvas**
- **Infinite canvas**: annotations can extend beyond original screenshot bounds (transparent fill)
- Zoom (pinch/scroll wheel) and pan (trackpad/scroll)
- **Undo/Redo** stack (`Cmd+Z` / `Cmd+Shift+Z`)
- **Non-destructive editing**: saves as `.snapper` project format (JSON metadata + original image + annotation layer data) alongside exported image

### Drawing Tools

| Tool | Shortcut | Details |
|---|---|---|
| **Arrow** | `A` | 4 styles: straight, curved, tapered, outlined. Color + stroke width configurable |
| **Rectangle** | `R` | Outlined or filled. Optional rounded corners. Color + stroke width |
| **Ellipse** | `E` | Outlined or filled. Color + stroke width |
| **Line** | `L` | Straight line. Color + stroke width. Optional dashed style |
| **Pencil** | `P` | Freeform drawing with auto-smoothing (Catmull-Rom spline). Color + stroke width |
| **Highlighter** | `H` | Semi-transparent wide stroke. Color + width |
| **Text** | `T` | Click to place, inline editing. Font, size, color, bold/italic. Background: none, rounded rect, pill. Monospace toggle |
| **Blur** | `B` | Drag to define rectangular area. Gaussian blur on underlying pixels. Adjustable intensity |
| **Pixelate** | `X` | Drag to define area. Mosaic pixelation with randomized block offsets. Adjustable block size |
| **Spotlight** | `S` | Select area to keep bright, dims everything else. Adjustable dim opacity |
| **Counter** | `N` | Click to place numbered markers. Toggle: numbers (1,2,3), letters (A,B,C), Roman numerals. Auto-increment, renumber on delete |
| **Crop** | `C` | Drag handles. Aspect ratio lock option. Snap to edges. Presets: 16:9, 4:3, 1:1, custom |

All tools share:
- Color picker (recent colors + custom)
- Stroke width slider
- Tool-specific options in a contextual toolbar

### Background Tool (Mockup Creator)
- Wraps screenshot in a decorative background for social media / presentations
- Built-in templates: gradients, solid colors, patterns
- Custom image background upload
- Adjustable padding, alignment, aspect ratio
- **Auto-balance**: automatically centers and pads the screenshot
- Exports as a new image (does not modify original)

### Editor Actions
- `Cmd+C` — Copy annotated image to clipboard
- `Cmd+S` — Save to default location
- `Cmd+Shift+S` — Save As (choose location + format)
- Share sheet integration (macOS system share)
- All tools accessible via keyboard shortcuts

---

## 6. Capture History & Storage

### History Database
- All captures stored locally
- **Storage location**: configurable (default `~/Library/Application Support/Snapper/History/`)
- Metadata in local **SQLite** database (via SwiftData): timestamp, capture type, dimensions, file path, tags, OCR text
- **Retention**: configurable (default 30 days, option for unlimited)

### History Browser
- Accessible from menu bar or dedicated hotkey
- Grid/list view of past captures
- Filter by capture type (area, fullscreen, window, scrolling, OCR)
- Search by OCR text content
- Re-open any capture in the annotation editor
- Delete individual captures or bulk clear
- Storage size indicator

### File Output
- **Default save directory**: configurable (default `~/Desktop`)
- **Filename pattern**: configurable with tokens — `Snapper {date} at {time}.png` (default)
  - Tokens: `{date}`, `{time}`, `{counter}`, `{app}`, `{type}`
- **Format**: PNG (default), JPEG (quality slider), TIFF
- **Retina-aware**: saves at actual pixel resolution (2x on Retina displays), with option to save at 1x

---

## 7. Settings & Preferences

### General
- Launch at login toggle
- Show/hide menu bar icon
- Capture sound on/off
- Default post-capture action: show overlay / copy to clipboard / save to file / open editor

### Shortcuts
- Full customizable hotkey editor for every action
- Conflict detection with system and other app shortcuts
- Reset to defaults button

### Capture
- Default file format + JPEG quality slider
- Filename pattern with token editor
- Default save directory picker
- Crosshair/magnifier toggle
- Freeze screen toggle
- Auto-hide desktop icons toggle
- Retina resolution (1x / 2x)
- Window capture: shadow, background style

### Overlay
- Screen corner position
- Thumbnail size
- Persistent until dismissed (enforced — no auto-close option)

### Floating Screenshots
- Default opacity
- Rounded corners / shadow / border toggles
- Remember positions across restarts

### History
- Storage location picker
- Retention period (days / unlimited)
- Clear all history button
- Storage size display

### Editor
- Default tool on open
- Default annotation color + stroke width
- Background tool template management

### About
- Version info
- GitHub repository link
- MIT license
- Sparkle auto-updater: check for updates, auto-update toggle

---

## 8. Permissions & Onboarding

### Required Permissions
1. **Screen Recording** — required for ScreenCaptureKit captures
2. **Accessibility** — required for global hotkey registration via CGEvent taps

### First-Run Flow
1. Welcome screen explaining what Snapper does
2. Request Screen Recording permission (system dialog)
3. Request Accessibility permission (opens System Settings)
4. Offer to disable macOS built-in screenshot shortcuts (guides user to System Settings > Keyboard > Shortcuts)
5. Configure default hotkeys
6. Ready to use

---

## 9. Architecture Overview

```
Snapper.app (LSUIElement agent)
├── AppDelegate / App lifecycle
├── MenuBarController (optional NSStatusItem)
├── HotkeyManager (CGEvent tap registration)
├── CaptureEngine
│   ├── ScreenCaptureKit integration
│   ├── AreaSelector (crosshair UI)
│   ├── WindowSelector (hover highlight)
│   ├── ScrollingCapture (scroll + stitch)
│   ├── OCRCapture (Vision framework)
│   └── TimerCapture (countdown overlay)
├── OverlayManager
│   ├── QuickAccessOverlay (NSPanel, stacking thumbnails)
│   └── PinnedScreenshot (NSPanel, floating windows)
├── AnnotationEditor
│   ├── CanvasView (Core Graphics rendering)
│   ├── ToolManager (all drawing tools)
│   ├── BackgroundTool (mockup creator)
│   └── ProjectFormat (.snapper file I/O)
├── HistoryManager
│   ├── SQLite/SwiftData store
│   └── HistoryBrowser (SwiftUI window)
├── SettingsManager
│   └── PreferencesWindow (SwiftUI)
└── UpdateManager (Sparkle framework)
```

### Key Dependencies
- **ScreenCaptureKit** (system framework) — capture
- **Vision** (system framework) — OCR
- **SwiftData** (system framework) — history persistence
- **Sparkle** (open source) — auto-updates
- No other third-party dependencies — keep the dependency tree minimal

---

## 10. Out of Scope (Explicitly Excluded)

- Cloud upload / sharing via URL
- Screen recording (video/GIF)
- Cross-platform support
- Plugin/extension system
- Collaboration features
- AI-powered features (smart selection, auto-annotation)
