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
    var targetLanguage: Locale.Language = Locale.Language(identifier: "zh-Hans")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "截图")
        rebuildMenu()

        ScreenPermission.requestIfNeeded()
    }

    func rebuildMenu() {
        statusItem.menu = StatusMenuBuilder.build(delegate: self)
    }

    // MARK: - Actions

    @objc func startScreenshot() {
        // 短暂延迟让菜单收起再展示 overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            SelectionOverlay.show { image in
                guard let image else { return }
                PinWindowController.create(image: image)
            }
        }
    }

    @objc func setTargetLanguage(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        targetLanguage = Locale.Language(identifier: identifier)
        rebuildMenu()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
