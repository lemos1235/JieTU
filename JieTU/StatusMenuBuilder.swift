//
//  StatusMenuBuilder.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit

@MainActor
enum StatusMenuBuilder {
    static func build(delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu()

        let screenshotItem = NSMenuItem(
            title: "截图",
            action: #selector(AppDelegate.startScreenshot),
            keyEquivalent: "a"
        )
        screenshotItem.target = delegate
        screenshotItem.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(screenshotItem)

        let autoOCRItem = NSMenuItem(
            title: "自动OCR",
            action: #selector(AppDelegate.toggleAutoOCR),
            keyEquivalent: ""
        )
        autoOCRItem.target = delegate
        autoOCRItem.state = delegate.autoOCREnabled ? .on : .off
        menu.addItem(autoOCRItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(AppDelegate.quit),
            keyEquivalent: "q"
        )
        quitItem.target = delegate
        menu.addItem(quitItem)

        return menu
    }
}
