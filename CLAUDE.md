# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Open `JieTU.xcodeproj` in Xcode and run with ⌘R, or build from the command line:

```bash
xcodebuild -project JieTU.xcodeproj -scheme JieTU -configuration Debug build
```

There are no automated tests in this project.

## Architecture

JieTU is a macOS menu bar screenshot app (accessory-policy, no Dock icon). Entry point is `JieTUApp.swift` (`@main`), which wires `AppDelegate` via `@NSApplicationDelegateAdaptor`.

### Flow

1. **Trigger** — `AppDelegate` registers a global hotkey (Cmd+Ctrl+A) via `GlobalHotKeyMonitor` (Carbon `RegisterEventHotKey`). The menu bar item also exposes the same action.
2. **Full-screen capture** — `AppDelegate.startScreenshot()` calls `ScreenCaptureManager.captureFullScreen(_:)` using ScreenCaptureKit (`SCScreenshotManager`).
3. **Region selection** — `AdjustmentOverlayController` (in `SelectionOverlay.swift`) presents a borderless full-screen `NSPanel` over the frozen screenshot. The user draws/adjusts a selection rect. An `OverlayMagnifierPanel` provides a pixel-level zoom preview near the cursor. An inline `Toolbar` appears inside the selection.
4. **Confirm** — On confirm, `ScreenCaptureManager.capture(rect:on:)` re-captures just the selected region. The result is passed to `PinWindowController.create(image:showsOCR:)`.
5. **Pin window** — `PinWindowController` creates a floating `NSPanel` (`.statusBar` level, joins all spaces) displaying the captured image. `PinContentContainerView` (in `PinWindowController.swift`) hosts either a plain image view or an `OCRAnalysisContainerView`. Multiple pin windows can coexist; they are tracked in `PinWindowController.all`.
6. **OCR** — `OCRAnalysisService` (in `OCRAnalysisSupport.swift`) runs VisionKit `ImageAnalyzer` (text + machine-readable codes) and `VNDetectBarcodesRequest` in parallel on a detached task. Results are shown via `ImageAnalysisOverlayView` overlaid on the image. Barcodes get custom drawn highlight rects with tooltip and right-click copy menu.

### Key files

| File | Responsibility |
|---|---|
| `AppDelegate.swift` | App lifecycle, hotkey registration, screenshot trigger |
| `ScreenCaptureManager.swift` | ScreenCaptureKit wrappers; also houses `CapturedImageView` and `PassiveHostingView` |
| `SelectionOverlay.swift` | Full-screen overlay panel, selection/resize/magnifier logic, `AdjustmentOverlayController` |
| `PinWindowController.swift` | Floating pin window (`NSPanel`), `PinContentContainerView`, context menu |
| `OCRAnalysisSupport.swift` | `OCRAnalysisService`, `OCRAnalysisContainerView`, barcode overlay drawing |
| `GlobalHotKeyMonitor.swift` | Carbon hot key registration wrapper |
| `StatusMenuBuilder.swift` | Menu bar menu construction |
| `Toolbar.swift` | Inline toolbar SwiftUI/AppKit view shown inside the selection rect |

### Coordinate systems

ScreenCaptureKit uses **global screen coordinates with bottom-left origin**. `SCStreamConfiguration.sourceRect` uses **display-local coordinates with top-left origin** (Quartz image space). `AdjustmentOverlayController` works in **overlay-view-local coordinates**. Vision `VNBarcodeObservation.boundingBox` is normalized with **bottom-left origin**, which matches `NSView`'s unflipped coordinate system directly (no Y-flip needed).

### Concurrency

All UI work is `@MainActor`. `ScreenCaptureManager` is a `@MainActor` enum that calls `async` ScreenCaptureKit APIs. OCR analysis is dispatched with `Task.detached(priority: .userInitiated)` and results are marshalled back with `await MainActor.run`.
