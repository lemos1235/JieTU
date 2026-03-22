//
//  ScreenPermission.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import ScreenCaptureKit

@MainActor
enum ScreenPermission {
    static func requestIfNeeded() {
        Task {
            do {
                // Attempting to get shareable content will trigger the permission prompt
                // if the user hasn't granted screen recording access yet.
                _ = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
            } catch {
                // Permission denied or not yet granted — open System Settings
                showPermissionAlert()
            }
        }
    }

    private static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "截图功能需要屏幕录制权限。请在「系统设置 → 隐私与安全性 → 屏幕录制」中为 jietu 启用权限，然后重新启动应用。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(
                string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            ) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
