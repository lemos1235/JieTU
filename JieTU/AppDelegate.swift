//
//  AppDelegate.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = true
            statusItem.button?.image = icon
        }
        rebuildMenu()

        ScreenPermission.requestIfNeeded()
    }

    func rebuildMenu() {
        statusItem.menu = StatusMenuBuilder.build(delegate: self)
    }

    // MARK: - Actions

    @objc func startScreenshot() {
        // 短暂延迟让菜单收起，再截图并展示自定义选区 overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task {
                guard let screen = NSScreen.main,
                      let fullImage = try? await ScreenCaptureManager.captureFullScreen(screen)
                else { return }
                AdjustmentOverlayController.show(
                    fullImage: fullImage, initialRect: nil, screen: screen
                )
            }
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
