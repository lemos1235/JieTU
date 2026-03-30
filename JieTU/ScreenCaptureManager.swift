//
//  ScreenCaptureManager.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import ScreenCaptureKit
import SwiftUI

/// 以等比缩放方式显示截图的 SwiftUI 视图。
struct CapturedImageView: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

/// 透传所有命中测试的 NSHostingView，使下方视图仍能响应鼠标事件。
final class PassiveHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
enum ScreenCaptureManager {
    /// 截图失败的错误类型。
    enum CaptureError: Error {
        case noDisplay
        case captureFailed
    }

    /// 截取全局屏幕坐标中指定区域的屏幕内容。
    static func capture(rect: CGRect, on screen: NSScreen) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        guard
            let display = content.displays.first(where: { scDisplay in
                scDisplay.frame.intersects(rect)
            })
        else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor

        // sourceRect 使用显示器本地坐标且原点在左上角，需将屏幕坐标（左下角原点）转换过来。
        let displayOrigin = display.frame.origin
        let localX = rect.origin.x - displayOrigin.x
        let localY = display.frame.height - (rect.origin.y - displayOrigin.y) - rect.height
        let localRect = CGRect(x: localX, y: localY, width: rect.width, height: rect.height)
        config.sourceRect = localRect
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.showsCursor = false
        config.capturesShadowsOnly = false
        config.shouldBeOpaque = true
        config.colorSpaceName = CGColorSpace.sRGB

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return NSImage(cgImage: cgImage, size: rect.size)
    }

    /// 以完整 Retina 分辨率截取整个屏幕（不裁剪 sourceRect）。
    static func captureFullScreen(_ screen: NSScreen) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        return try await captureFullScreen(screen, content: content)
    }

    /// 同上，但接受预先获取的 SCShareableContent，避免重复枚举。
    static func captureFullScreen(_ screen: NSScreen, content: SCShareableContent) async throws -> NSImage {
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
        config.colorSpaceName = CGColorSpace.sRGB
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return NSImage(cgImage: cgImage, size: screen.frame.size)
    }
}
