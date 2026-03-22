//
//  PinWindowController.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Result Panel

/// A lightweight floating panel that shows OCR / translation text results.
final class ResultPanel: NSPanel {
    init(text: String, title: String) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.title = title
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces]
        let textView = NSTextView()
        textView.string = text
        textView.isEditable = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        contentView = scroll
    }
    override var canBecomeKey: Bool { true }
}

// MARK: - Controller

@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate {

    private static var all: [PinWindowController] = []

    private let image: NSImage
    private let toolbarPanel: PinToolbarPanel
    private var toolbarHosting: NSHostingView<PinToolbarView>!
    private var toolbarView: PinToolbarView!
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var resultPanels: [ResultPanel] = []

    // MARK: Factory

    static func create(image: NSImage, initialFrame: CGRect? = nil) {
        let ctrl = PinWindowController(image: image, initialFrame: initialFrame)
        all.append(ctrl)
        ctrl.showWindow(nil)
    }

    // MARK: Init

    init(image: NSImage, initialFrame: CGRect? = nil) {
        self.image = image
        self.toolbarPanel = PinToolbarPanel()

        let windowFrame: CGRect
        if let initialFrame {
            windowFrame = initialFrame
        } else {
            // Size pin window to image (max 60% of screen)
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let maxSize = CGSize(
                width: screen.visibleFrame.width * 0.6,
                height: screen.visibleFrame.height * 0.6)
            let scale = min(
                1.0,
                min(
                    maxSize.width / image.size.width,
                    maxSize.height / image.size.height))
            let winSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale)
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

        // Pin mode keeps only the sticker surface visible.
        pinWindow.onDragBegan = { [weak self] in self?.toolbarPanel.orderOut(nil) }
        pinWindow.onDragEnded = { [weak self] in self?.toolbarPanel.orderOut(nil) }

        // Build toolbar SwiftUI view (capture self weakly)
        setupToolbar(pinWindow: pinWindow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Toolbar Setup

    private func setupToolbar(pinWindow: PinWindow) {
        let tv = PinToolbarView(
            onClose: { [weak self] in self?.closePin() },
            onPin: nil,
            onTranslate: { [weak self] in self?.performTranslate() },
            onSave: { [weak self] in self?.saveImage() },
            onCopy: { [weak self] in self?.copyImage() }
        )
        self.toolbarView = tv
        let hosting = NSHostingView(rootView: tv)
        self.toolbarHosting = hosting
        toolbarPanel.contentView = hosting
        toolbarPanel.level = NSWindow.Level(rawValue: pinWindow.level.rawValue + 1)

        // Reposition toolbar when window moves (drag callbacks handle hide/show)
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: pinWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.repositionToolbar() }
        }

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: pinWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.repositionToolbar() }
        }
    }

    // MARK: Window lifecycle

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        toolbarPanel.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        toolbarPanel.orderOut(nil)
        if let obs = moveObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = resizeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        resultPanels.forEach { $0.orderOut(nil) }
        PinWindowController.all.removeAll { $0 === self }
    }

    // MARK: Toolbar positioning

    private func repositionToolbar() {
        guard let win = window else { return }
        let toolbarWidth = max(220, min(win.frame.width, 440))
        let toolbarHeight: CGFloat = 52
        let winFrame = win.frame
        let x = winFrame.midX - toolbarWidth / 2
        let y = winFrame.minY - toolbarHeight - 6
        toolbarPanel.setFrame(
            CGRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight),
            display: true
        )
    }

    // MARK: - Toolbar Actions

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

    private func performTranslate() {
        Task {
            defer { updateToolbarBusy() }
            do {
                let lines = try await OCRManager.recognize(image: image)
                guard !lines.isEmpty else {
                    showResult(text: "未识别到可翻译的文字", title: "翻译")
                    return
                }
                let source = lines.joined(separator: "\n")
                let targetLang =
                    (NSApp.delegate as? AppDelegate)?.targetLanguage
                    ?? Locale.Language(identifier: "zh-Hans")
                let translated = try await TranslationManager.shared.translate(
                    source, to: targetLang)
                showResult(text: "原文：\n\(source)\n\n译文：\n\(translated)", title: "翻译结果")
            } catch {
                showResult(text: "翻译失败：\(error.localizedDescription)", title: "翻译")
            }
        }
    }

    private func showResult(text: String, title: String) {
        let panel = ResultPanel(text: text, title: title)
        // Position result panel to the right of the pin window
        if let win = window {
            panel.level = NSWindow.Level(rawValue: win.level.rawValue + 1)
            let x = win.frame.maxX + 8
            let y = win.frame.maxY - 200
            panel.setFrameOrigin(CGPoint(x: x, y: y))
        }
        resultPanels.append(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    private func updateToolbarBusy() {
        // Rebuild toolbar to reset busy spinners
        // SwiftUI state is owned by the view; we signal via a fresh view replacement
        let tv = PinToolbarView(
            onClose: { [weak self] in self?.closePin() },
            onPin: nil,
            onTranslate: { [weak self] in self?.performTranslate() },
            onSave: { [weak self] in self?.saveImage() },
            onCopy: { [weak self] in self?.copyImage() }
        )
        self.toolbarView = tv
        toolbarHosting.rootView = tv
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
            .background(
                Rectangle()
                    .stroke(pinGlow.opacity(0.9), lineWidth: 2)
                    .blur(radius: 4)
                    .shadow(color: pinGlow.opacity(0.55), radius: 12, x: 0, y: 0)
                    .shadow(color: pinGlow.opacity(0.30), radius: 24, x: 0, y: 0)
                    .shadow(color: pinGlow.opacity(0.15), radius: 40, x: 0, y: 0)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class PinImageContainerView: NSView {
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    private let hostingView: NSHostingView<PinImageView>

    init(image: NSImage) {
        self.hostingView = NSHostingView(rootView: PinImageView(image: image))
        super.init(frame: .zero)
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: "复制当前图像", action: #selector(handleCopy), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let saveItem = NSMenuItem(title: "另存为图片", action: #selector(handleSave), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        menu.addItem(.separator())

        let closeItem = NSMenuItem(
            title: "关闭该贴图", action: #selector(handleClose), keyEquivalent: "")
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
