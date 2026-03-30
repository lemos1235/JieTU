//
//  AppDelegate.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    private var screenshotHotKeyMonitor: GlobalHotKeyMonitor?
    private var screenshotTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = true
            statusItem.button?.image = icon
        }
        rebuildMenu()
        registerScreenshotHotKey()

        ScreenPermission.requestIfNeeded()
    }

    func applicationWillTerminate(_: Notification) {
        screenshotTask?.cancel()
        screenshotTask = nil
        screenshotHotKeyMonitor = nil
    }

    func rebuildMenu() {
        statusItem.menu = StatusMenuBuilder.build(delegate: self)
    }

    private func registerScreenshotHotKey() {
        screenshotHotKeyMonitor = GlobalHotKeyMonitor(
            id: 0x4A545348,
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(controlKey) | UInt32(cmdKey)
        ) { [weak self] in
            self?.startScreenshot()
        }
    }

    private func preferredCaptureScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    @objc func startScreenshot() {
        guard screenshotTask == nil, AdjustmentOverlayController.active == nil else { return }

        // 短暂延迟让菜单收起，再截图并展示自定义选区 overlay
        screenshotTask = Task { [weak self] in
            defer { self?.screenshotTask = nil }

            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled,
                  AdjustmentOverlayController.active == nil,
                  let self
            else { return }

            guard let screen = preferredCaptureScreen(),
                  let fullImage = try? await ScreenCaptureManager.captureFullScreen(screen)
            else { return }
            AdjustmentOverlayController.show(
                fullImage: fullImage, initialRect: nil, screen: screen
            )
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
