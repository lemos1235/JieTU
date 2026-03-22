//
//  PinWindow.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit

final class PinWindow: NSPanel {

    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onDragBegan?()
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onDragEnded?()
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        backgroundColor = .clear
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
