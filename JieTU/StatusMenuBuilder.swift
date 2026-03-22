//
//  StatusMenuBuilder.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit

@MainActor
enum StatusMenuBuilder {
    static let languages: [(title: String, identifier: String)] = [
        ("简体中文", "zh-Hans"),
        ("English", "en"),
        ("日本語", "ja"),
        ("한국어", "ko"),
    ]

    static func build(delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu()

        let screenshotItem = NSMenuItem(
            title: "截图并贴图",
            action: #selector(AppDelegate.startScreenshot),
            keyEquivalent: ""
        )
        screenshotItem.target = delegate
        screenshotItem.image = NSImage(
            systemSymbolName: "camera.viewfinder", accessibilityDescription: nil
        )
        menu.addItem(screenshotItem)

        menu.addItem(.separator())

        // Language submenu
        let langItem = NSMenuItem(title: "翻译目标语言", action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu(title: "翻译目标语言")
        let currentIdentifier = delegate.targetLanguage.minimalIdentifier
        for lang in languages {
            let item = NSMenuItem(
                title: lang.title,
                action: #selector(AppDelegate.setTargetLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = delegate
            item.representedObject = lang.identifier
            if lang.identifier == currentIdentifier {
                item.state = .on
            }
            langSubmenu.addItem(item)
        }
        langItem.submenu = langSubmenu
        menu.addItem(langItem)

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
