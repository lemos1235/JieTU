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
            keyEquivalent: ""
        )
        screenshotItem.target = delegate
        screenshotItem.image = NSImage(
            systemSymbolName: "camera.viewfinder", accessibilityDescription: nil
        )
        menu.addItem(screenshotItem)

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
