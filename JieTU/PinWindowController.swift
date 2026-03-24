//
//  PinWindowController.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Shared inset between the pin window frame and the image content view.
/// Used by both `PinWindowController` (to expand `initialFrame`) and
/// `PinContentContainerView` (to inset its content view).
let pinContentInset: CGFloat = 6

@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate {
    private static var all: [PinWindowController] = []

    private let image: NSImage
    private let contentContainer: PinContentContainerView

    // MARK: Factory

    static func create(image: NSImage, initialFrame: CGRect? = nil, showsOCR: Bool = false) {
        let ctrl = PinWindowController(
            image: image,
            initialFrame: initialFrame,
            showsOCR: showsOCR
        )
        all.append(ctrl)
        ctrl.showWindow(nil)
        ctrl.window?.orderFrontRegardless()
        ctrl.beginOCRAnalysisIfNeeded()
    }

    // MARK: Init

    init(image: NSImage, initialFrame: CGRect? = nil, showsOCR: Bool = false) {
        self.image = image

        let windowFrame: CGRect
        if let initialFrame {
            // Expand by pinContentInset so the inner image view is exactly the selection size
            windowFrame = initialFrame.insetBy(dx: -pinContentInset, dy: -pinContentInset)
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
        if showsOCR {
            // OCR mode: left-click is reserved for text selection; drag handled by OCRAnalysisContainerView
            pinWindow.isMovableByWindowBackground = false
        }
        contentContainer = PinContentContainerView(image: image, showsOCR: showsOCR)
        super.init(window: pinWindow)

        contentContainer.onCopy = { [weak self] in self?.copyImage() }
        contentContainer.onSave = { [weak self] in self?.saveImage() }
        contentContainer.onClose = { [weak self] in self?.closePin() }
        pinWindow.contentView = contentContainer
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

    private func beginOCRAnalysisIfNeeded() {
        contentContainer.beginOCRAnalysis()
    }

}

final class PinContentContainerView: NSView {
    var onCopy: (() -> Void)? { didSet { ocrContainerView?.onCopy = onCopy } }
    var onSave: (() -> Void)? { didSet { ocrContainerView?.onSave = onSave } }
    var onClose: (() -> Void)? { didSet { ocrContainerView?.onClose = onClose } }

    private let contentInset: CGFloat = pinContentInset
    private let contentView: NSView
    private let ocrContainerView: OCRAnalysisContainerView?

    init(image: NSImage, showsOCR: Bool) {
        if showsOCR {
            let ocrView = OCRAnalysisContainerView(image: image, showsBorder: true)
            contentView = ocrView
            ocrContainerView = ocrView
        } else {
            let hostingView = NSHostingView(
                rootView: CapturedImageView(image: image, showsBorder: true)
            )
            contentView = hostingView
            ocrContainerView = nil
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(contentView)
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
        contentView.frame = bounds.insetBy(dx: contentInset, dy: contentInset)
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

    func beginOCRAnalysis() {
        ocrContainerView?.beginAnalysis()
    }
}
