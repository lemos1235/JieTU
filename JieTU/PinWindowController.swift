//
//  PinWindowController.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate {
    private static var all: [PinWindowController] = []

    private let image: NSImage

    // MARK: Factory

    static func create(image: NSImage, initialFrame: CGRect? = nil) {
        let ctrl = PinWindowController(image: image, initialFrame: initialFrame)
        all.append(ctrl)
        ctrl.showWindow(nil)
        ctrl.window?.orderFrontRegardless()
    }

    // MARK: Init

    init(image: NSImage, initialFrame: CGRect? = nil) {
        self.image = image

        let windowFrame: CGRect
        if let initialFrame {
            windowFrame = initialFrame
        } else {
            // Size pin window to image (max 60% of screen)
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let maxSize = CGSize(
                width: screen.visibleFrame.width * 0.6,
                height: screen.visibleFrame.height * 0.6
            )
            let scale = min(
                1.0,
                min(
                    maxSize.width / image.size.width,
                    maxSize.height / image.size.height
                )
            )
            let winSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            let origin = CGPoint(
                x: screen.visibleFrame.midX - winSize.width / 2,
                y: screen.visibleFrame.midY - winSize.height / 2
            )
            windowFrame = CGRect(origin: origin, size: winSize)
        }
        let pinWindow = PinWindow(contentRect: windowFrame)
        pinWindow.contentAspectRatio = image.size
        super.init(window: pinWindow)

        // Image content
        let imageView = PinImageContainerView(image: image)
        imageView.onCopy = { [weak self] in self?.copyImage() }
        imageView.onSave = { [weak self] in self?.saveImage() }
        imageView.onClose = { [weak self] in self?.closePin() }
        pinWindow.contentView = imageView
        pinWindow.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: Window lifecycle

    func windowWillClose(_: Notification) {
        PinWindowController.all.removeAll { $0 === self }
    }

    // MARK: - Actions

    private func closePin() {
        window?.close()
    }

    private func copyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screenshot.png"
        if let win = window {
            panel.level = NSWindow.Level(rawValue: win.level.rawValue + 1)
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            if let tiff = self.image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:])
            {
                try? png.write(to: url)
            }
        }
    }

}

// MARK: - SwiftUI image view

struct PinImageView: View {
    let image: NSImage
    private let pinGlow = Color(red: 0.29, green: 0.58, blue: 1.0)

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay(
                Rectangle()
                    .stroke(pinGlow, lineWidth: 1)
                    .shadow(color: pinGlow, radius: 4, x: 0, y: 0)
            )
    }
}

final class PinImageContainerView: NSView {
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    private let hostingView: NSHostingView<PinImageView>

    init(image: NSImage) {
        hostingView = NSHostingView(rootView: PinImageView(image: image))
        super.init(frame: .zero)
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: "复制当前图像", action: #selector(handleCopy), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let saveItem = NSMenuItem(title: "另存为图片", action: #selector(handleSave), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        menu.addItem(.separator())

        let closeItem = NSMenuItem(
            title: "关闭该贴图", action: #selector(handleClose), keyEquivalent: ""
        )
        closeItem.target = self
        menu.addItem(closeItem)

        return menu
    }

    @objc
    private func handleCopy() {
        onCopy?()
    }

    @objc
    private func handleSave() {
        onSave?()
    }

    @objc
    private func handleClose() {
        onClose?()
    }
}
