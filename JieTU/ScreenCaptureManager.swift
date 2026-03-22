//
//  ScreenCaptureManager.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import ScreenCaptureKit

@MainActor
enum ScreenCaptureManager {
    enum CaptureError: Error {
        case noDisplay
        case captureFailed
    }

    /// Capture a region of the screen specified in global screen coordinates.
    static func capture(rect: CGRect, on screen: NSScreen) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        // Find the SCDisplay that corresponds to the given NSScreen
        guard
            let display = content.displays.first(where: { scDisplay in
                // SCDisplay.frame is in global screen coordinates (bottom-left origin)
                scDisplay.frame.intersects(rect)
            })
        else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor

        // sourceRect must be in display-local coordinates with top-left origin (Quartz image space),
        // but rect and display.frame use macOS screen coordinates (bottom-left origin).
        let displayOrigin = display.frame.origin
        let localX = rect.origin.x - displayOrigin.x
        // Flip Y: screen coords have origin at bottom; sourceRect wants origin at top.
        let localY = display.frame.height - (rect.origin.y - displayOrigin.y) - rect.height
        let localRect = CGRect(x: localX, y: localY, width: rect.width, height: rect.height)
        config.sourceRect = localRect
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.showsCursor = false
        config.capturesShadowsOnly = false
        config.shouldBeOpaque = true

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return NSImage(cgImage: cgImage, size: rect.size)
    }

    /// Capture an entire screen (no sourceRect crop) at full Retina resolution.
    static func captureFullScreen(_ screen: NSScreen) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.frame.intersects(screen.frame) })
        else {
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        config.showsCursor = false
        config.capturesShadowsOnly = false
        config.shouldBeOpaque = true
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return NSImage(cgImage: cgImage, size: screen.frame.size)
    }
}
