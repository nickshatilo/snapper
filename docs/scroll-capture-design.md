# Scroll Capture Design

## Goal

Add a real scroll-capture mode to Snapper that works for:

- long web pages in browsers
- scrollable panes inside Electron apps
- any other on-screen scrollable region that can be automatically scrolled

The product requirement is:

1. the user selects the target region
2. Snapper scrolls it automatically
3. Snapper captures a live video stream during the run
4. Snapper stitches the newly revealed content into one tall screenshot

The user should not need to scroll manually.

## Why video-first

The current app only captures still frames through `SCScreenshotManager`, which is good for static screenshots but not for scrolling content. For scroll capture, video frames are the right primitive because:

- websites, Electron apps, PDFs, and native scroll views all reduce to pixels on screen
- internal scroll areas often do not map cleanly to a whole window
- visual stitching works even when we cannot introspect the app
- automatic scrolling still needs visual confirmation, because a requested AX or wheel scroll may be ignored

This should use `ScreenCaptureKit` streaming via `SCStream`, not a sequence of discrete screenshots.

## Product Shape

Add a new `CaptureMode.scroll`.

The user flow should be:

1. Start `Scroll Capture`.
2. Select the scrollable region.
3. Snapper identifies the likely scroll target near the center of that region.
4. Snapper starts a live capture session for that region.
5. Snapper auto-scrolls in small verified steps until the content stops moving.
6. Snapper outputs a single tall screenshot through the normal result pipeline.

This should feel like a single-command capture mode, not an assisted recording tool.

## Recommended Rollout

### Phase 1

Ship an auto-scroll, area-based capture with video verification.

Scope:

- area selection only
- vertical scrolling only
- one dominant direction per session
- Accessibility-backed or synthetic-wheel auto-scroll
- output as normal image capture

This gives the product the right behavior from day one: the app does the scrolling.

### Phase 2

Improve targeting and robustness.

Scope:

- better scroll target discovery inside complex windows
- window preselection shortcut for obvious cases
- stronger sticky header/footer masking
- retry logic for failed scroll steps

### Phase 3

Improve large-output handling.

Scope:

- editor support for very tall captures
- tile-based export for extremely large results
- optional PDF export for outputs that exceed practical bitmap limits

## Architecture

### New components

#### `ScrollCaptureCoordinator`

Owns the end-to-end session:

- launches selection UI
- starts/stops stream capture
- shows a small floating controller
- drives stitching
- emits a final `CaptureResult`

This should be called from `CaptureCoordinator` when `CaptureMode.scroll` is selected.

#### `ScrollCaptureSession`

A state container for one session:

- selected screen rect
- active display and scale
- stream timestamps
- detected scroll direction
- cumulative stitched height
- confidence and failure state

Keep this separate from UI so the stitching pipeline can be tested.

#### `ScrollCaptureRecorder`

Wraps `SCStream` and yields video frames for a selected region.

Responsibilities:

- configure `SCContentFilter` for the display containing the region
- stream frames at a modest rate, around 12-20 fps
- crop each frame down to the selected region in display coordinates
- hand off `CGImage` or pixel buffers to the estimator

This belongs beside the existing capture services, but should not overload `ScreenCaptureService` with session orchestration logic.

#### `ScrollMotionEstimator`

Computes the relative offset between accepted frames.

Responsibilities:

- downscale to a working width
- convert to grayscale
- ignore the outer margins where shadows and scrollbars live
- estimate vertical translation
- return a confidence score

This should be a pure, unit-testable type.

#### `ScrollStitcher`

Builds the final tall image incrementally.

Responsibilities:

- track cumulative scroll offset
- append only newly exposed strips
- blend seams when needed
- manage memory limits

For the first version this can be an in-memory bitmap while the total height stays reasonable. It should be designed so it can later swap to a tiled backing store.

#### `AutoScroller`

Core session component responsible for driving the content.

Responsibilities:

- locate the scroll target under the selected point
- attempt AX scroll actions first
- fall back to synthetic scroll wheel events
- wait for real motion confirmation from the estimator before issuing the next step
- decide when the session has reached the end

This is not optional. Scroll capture mode depends on it.

## Capture Pipeline

### 1. Region selection

Reuse the area-selection overlay, but present copy that makes the constraint clear:

- "Select the scrolling content area"
- "Exclude fixed browser chrome when possible"

Area selection is more important than window selection here because many real targets are nested panes inside a larger window.

### 2. Live frame capture

Use `SCStream` on the display containing the region. Capture the whole display frame at stream resolution, then crop to the selected rect. This is simpler and more reliable than trying to stream a custom sub-rectangle directly through app-specific logic.

Suggested config:

- `showsCursor = false`
- fixed frame rate target around 15 fps
- width scaled to a reasonable working resolution
- preserve Retina output for final stitched strips

The stream does not need to be saved as a user-visible movie file. The frames are the source data.

### 3. Verified scroll loop

For each auto-scroll step:

1. issue a scroll action
2. wait for a new stable frame
3. estimate movement against the last accepted frame
4. reject the step if confidence is low
5. retry with smaller or alternate scroll input if needed
6. accept the frame only when enough new content was revealed

The estimator is the authority. A requested scroll that produces no real motion should not advance the stitcher.

### 4. Frame acceptance

Do not stitch every frame.

For each new frame:

1. preprocess it
2. estimate movement against the last accepted frame
3. reject frames with low confidence or near-zero movement
4. accept frames only when they reveal enough new content

This keeps noise and memory usage under control.

### 5. Stitching

For a downward scroll:

- compute overlap between previous accepted frame and current frame
- append only the newly revealed bottom band
- update cumulative height

For an upward scroll:

- the same logic applies in reverse

For MVP, support a single dominant direction and stop if motion reverses unexpectedly. In an auto-driven flow, reversal is a control bug, not normal user behavior.

## Motion Estimation Strategy

The critical part is estimating how far the content moved between frames.

Use a visual approach that assumes mostly vertical motion with minor horizontal jitter.

### Preprocessing

For each candidate frame:

- crop out a small border on all sides
- optionally exclude the rightmost strip to avoid scrollbars
- convert to grayscale
- downscale to a stable working size

### Matching

Use multiple horizontal anchor bands across the image instead of one full-frame comparison.

For each band:

- compare the previous accepted frame and current frame across a search window of likely vertical offsets
- compute a similarity score such as normalized cross-correlation or sum of absolute differences

Then:

- take the median shift of the best bands
- reject outliers
- compute a confidence score from band agreement

This is more robust against:

- sticky headers
- floating chat widgets
- videos or animated ads
- partially obscured sidebars

### Sticky regions

Sticky headers and footers are the main source of bad seams.

The estimator should maintain a dynamic row mask:

- rows that repeatedly appear stationary while the rest of the frame moves are likely pinned UI
- those rows should be removed from future matching and overlap decisions

For the first version, a simpler rule is acceptable:

- ignore the top and bottom 10-15% of the frame during matching

That will already handle most browser chrome and many sticky headers.

## Stitching Strategy

The stitcher should operate on accepted full-resolution frames.

Given an accepted vertical shift:

- treat the overlapping region as already represented
- extract only the non-overlapping strip
- append that strip to the composite

Seams:

- start with a hard cut at the computed overlap boundary
- if visible seam artifacts appear, add a small feather blend across a narrow overlap band

This is enough for rendered UI because most scroll capture content already aligns sharply when the shift is correct.

## Memory and Output Limits

Very tall bitmaps can become impractical quickly.

Risks:

- large `CGContext` allocations
- very tall `CGImage` export failures
- annotation editor becoming hard to use with extremely tall images

Design for these limits up front:

- keep an internal megapixel or byte budget
- if the capture exceeds that budget, spill strips to a tile store on disk
- define a maximum editor-open threshold

Reasonable first behavior:

- stitch in memory up to a safe limit
- save larger captures directly to disk
- skip automatic editor opening for oversized results

If height exceeds practical bitmap limits, export as PDF in a later phase.

## Auto-Scroll Design

Auto-scroll is the mode.

Flow:

1. user selects region
2. Snapper identifies the scroll target near the region center
3. Snapper issues a scroll step
4. the estimator confirms real movement
5. Snapper appends newly revealed content
6. Snapper issues the next step
7. Snapper stops when the end is reached or retries are exhausted

Key rule:

The estimator is authoritative. Do not assume a requested AX or wheel event produced motion.

### Target discovery

Try, in order:

1. Accessibility element at the region center
2. nearest ancestor with scroll actions or scroll bar attributes
3. synthetic wheel events delivered at the selected point

This means:

- native apps may auto-scroll cleanly through AX
- browsers and Electron apps may work through wheel events even when AX metadata is weak

### Failure handling

If auto-scroll fails to produce confident motion after a few attempts:

- stop the session
- preserve any valid stitched result if there is one
- show a short explanation such as `Couldn’t control this scroll area reliably`

There should be no fallback into manual scrolling.

## UI Integration

### Capture entry points

Update:

- `Snapper/Capture/CaptureMode.swift`
- `Snapper/Capture/CaptureCoordinator.swift`
- `Snapper/Capture/AllInOneHUD/AllInOneHUDView.swift`
- `Snapper/MenuBar/MenuBarMenu.swift`
- `Snapper/Hotkeys/HotkeyAction.swift`

Add a new menu item and HUD button for `Scroll`.

### In-session controls

Add a small floating controller with:

- `Stop`
- `Pause`
- live status such as `Scrolling...`, `Retrying...`, or `Reached end`
- an optional progress hint based on cumulative stitched height

Avoid a large HUD; it should not cover content.

### Result handling

Reuse the existing `CaptureResult` / history / quick access flow so scroll captures behave like normal screenshots after generation.

History should store `captureType = scroll`.

## Codebase Integration Points

### Existing files to extend

- `Snapper/Capture/CaptureMode.swift`
- `Snapper/Capture/CaptureCoordinator.swift`
- `Snapper/Capture/ScreenCaptureService.swift`
- `Snapper/App/AppState.swift`
- `Snapper/App/Constants.swift`
- `Snapper/Settings/SettingsView.swift`
- `Snapper/History/Models/CaptureRecord.swift`

### New files to add

- `Snapper/Capture/ScrollCapture/ScrollCaptureCoordinator.swift`
- `Snapper/Capture/ScrollCapture/ScrollCaptureSession.swift`
- `Snapper/Capture/ScrollCapture/ScrollCaptureRecorder.swift`
- `Snapper/Capture/ScrollCapture/ScrollMotionEstimator.swift`
- `Snapper/Capture/ScrollCapture/ScrollStitcher.swift`
- `Snapper/Capture/ScrollCapture/ScrollCaptureControlPanel.swift`
- `Snapper/Capture/ScrollCapture/AutoScroller.swift`

Keep the estimator and stitcher mostly free of AppKit UI dependencies so they can be tested in isolation.

## Settings

Avoid too many knobs in the first version.

The only settings worth exposing early are:

- whether to open the editor automatically after completion
- whether Snapper should prefer AX scrolling before synthetic wheel events

Keep frame rate, confidence thresholds, overlap search ranges, and memory budgets internal until real-world testing proves they need to be user-facing.

## Testing Plan

### Unit tests

Add synthetic tests for:

- pure downward shift detection
- pure upward shift detection
- sticky header present
- animated region present
- low-confidence rejection
- seam append math

These tests should operate on generated grayscale buffers, not screenshots checked into the repo.

### Manual verification

Validate against:

- Safari long article
- Chrome or Arc documentation page
- Slack or Discord channel in Electron
- Notion or Linear desktop app
- PDF in Preview

Check:

- stitched continuity
- header/footer artifact handling
- tall image export
- oversize result behavior

## Recommendation

Build Phase 1 as:

- area-based
- auto-scrolled
- video-driven
- vertical-only stitching

The critical implementation bet is a verified control loop:

1. issue scroll input
2. confirm actual motion from the video stream
3. stitch only confirmed new content

That keeps the feature app-agnostic while still delivering the fully automatic behavior the product wants.
